defmodule LightningWeb.WebhooksController do
  use LightningWeb, :controller

  alias Lightning.Extensions.RateLimiting
  alias Lightning.Invocation.RequestHeaders
  alias Lightning.Retry
  alias Lightning.Services.RateLimiter
  alias Lightning.Workflows
  alias Lightning.WorkOrders

  require Logger

  plug :reject_unfetched when action in [:create]

  defp reject_unfetched(conn, _) do
    case conn.body_params do
      %Plug.Conn.Unfetched{} ->
        conn
        |> put_status(415)
        |> put_view(LightningWeb.ErrorView)
        |> render(:"415")
        |> halt()

      _ ->
        conn
    end
  end

  @spec check(Plug.Conn.t(), map) :: Plug.Conn.t()
  def check(conn, _params) do
    put_status(conn, :ok)
    |> json(%{
      message:
        "OpenFn webhook trigger found. Make a POST request to execute this workflow."
    })
  end

  @spec create(Plug.Conn.t(), map) :: Plug.Conn.t()
  def create(conn, _params) do
    with %Workflows.Trigger{enabled: true, workflow: %{project_id: project_id}} =
           trigger <- conn.assigns[:trigger],
         {:ok, run_rejection} <- check_skip_run_creation(project_id),
         :ok <-
           RateLimiter.limit_request(
             conn,
             %RateLimiting.Context{project_id: project_id},
             []
           ) do
      Retry.with_webhook_retry(
        fn ->
          WorkOrders.create_for(trigger,
            workflow: trigger.workflow,
            dataclip: %{
              body: conn.body_params,
              request: build_request(conn, trigger),
              type: :http_request,
              project_id: project_id
            },
            without_run: not is_nil(run_rejection)
          )
        end,
        retry_on: &Retry.retriable_error?/1,
        context: %{trigger_id: trigger.id, workflow_id: trigger.workflow.id}
      )
      |> case do
        {:ok, work_order} ->
          conn
          |> put_work_order_headers(work_order)
          |> respond_to_created(trigger, work_order, run_rejection)

        {:error, %DBConnection.ConnectionError{} = error} ->
          LightningWeb.Utils.respond_service_unavailable(
            conn,
            error,
            %{
              op: :create_workorder,
              trigger_id: trigger.id,
              workflow_id: trigger.workflow.id,
              project_id: project_id
            },
            message:
              "Unable to process request due to temporary database issues. Please try again in %{s}s.",
            halt?: false
          )

        {:error, %Ecto.Changeset{} = changeset} ->
          errors = Ecto.Changeset.traverse_errors(changeset, fn {m, _} -> m end)

          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: :invalid_request, details: errors})

        {:error, reason} when is_atom(reason) ->
          conn
          |> put_status(:unprocessable_entity)
          |> json(%{error: reason})
      end
    else
      {:error, reason, %{text: message}} ->
        conn
        |> put_status(:too_many_requests)
        |> json(%{error: reason, message: message})

      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{"error" => "Webhook not found"})

      _disabled ->
        put_status(conn, :forbidden)
        |> json(%{
          error: :trigger_disabled,
          message:
            "Unable to process request, trigger is disabled. Enable it on OpenFn to allow requests to this endpoint."
        })
    end
  end

  defp put_work_order_headers(conn, work_order) do
    conn
    |> put_resp_header("x-meta-work-order-id", work_order.id)
    |> then(fn conn ->
      case work_order do
        %{runs: [run]} -> put_resp_header(conn, "x-meta-run-id", run.id)
        _ -> conn
      end
    end)
  end

  defp respond_to_created(conn, trigger, work_order, run_rejection) do
    cond do
      # Only wait when a run exists to answer the wait: the sole publisher of
      # `{:webhook_response, ...}` lives on a run's channel, so a run-less work
      # order would park this process until the response timeout.
      Workflows.Trigger.synchronous?(trigger) and has_run?(work_order) ->
        handle_delayed_response(conn, work_order)

      Workflows.Trigger.synchronous?(trigger) ->
        respond_without_run(conn, work_order, run_rejection)

      true ->
        json(
          conn,
          Map.merge(
            %{work_order_id: work_order.id},
            rejection_details(run_rejection)
          )
        )
    end
  end

  # The limiter's own message is deliberately not echoed here: it is copy written
  # for the project UI, and `/i/*` is anonymous whenever the trigger carries no
  # auth methods. The reason code says why no run was created without disclosing
  # a project's plan or quota wording to whoever holds the webhook URL.
  defp rejection_details(nil), do: %{}
  defp rejection_details(reason) when is_atom(reason), do: %{error: reason}

  defp has_run?(%{runs: [_ | _]}), do: true
  defp has_run?(_work_order), do: false

  # A synchronous request whose work order carries no run can never be answered
  # by a completion broadcast, so reply now with the reason the run was not
  # created rather than holding the connection open for the full timeout.
  defp respond_without_run(conn, work_order, run_rejection) do
    status =
      if is_nil(run_rejection) do
        Logger.warning(
          "Synchronous webhook work order created without a run: " <>
            inspect(work_order.id)
        )

        :internal_server_error
      else
        :too_many_requests
      end

    conn
    |> put_status(status)
    |> json(
      Map.merge(
        %{work_order_id: work_order.id},
        rejection_details(run_rejection || :no_run_created)
      )
    )
  end

  defp handle_delayed_response(conn, work_order) do
    topic = "work_order:#{work_order.id}:webhook_response"
    Phoenix.PubSub.subscribe(Lightning.PubSub, topic)

    receive do
      {:webhook_response, status_code, _body} when status_code in [204, 304] ->
        send_resp(conn, status_code, "")

      {:webhook_response, status_code, body} ->
        conn
        |> put_status(status_code)
        |> json(body)
    after
      Lightning.Config.webhook_response_timeout_ms() ->
        Logger.warning(
          "Webhook response timeout for work_order: #{inspect(work_order.id)}"
        )

        conn
        |> put_status(:gateway_timeout)
        |> json(%{
          error: :timeout,
          message: "Workflow did not complete within timeout period",
          work_order_id: work_order.id
        })
    end
  end

  # `{:error, :too_many_runs, _}` is not fatal: the payload is still recorded as
  # a rejected work order, just without a run. The reason travels with that
  # decision instead of being collapsed into a bare boolean, so the response can
  # say why no run was created.
  defp check_skip_run_creation(project_id) do
    case WorkOrders.limit_run_creation(project_id) do
      :ok ->
        {:ok, nil}

      {:error, :too_many_runs, _message} ->
        {:ok, :too_many_runs}

      error ->
        error
    end
  end

  defp build_request(%Plug.Conn{} = conn, %Workflows.Trigger{} = trigger) do
    %{
      method: conn.method,
      path: conn.path_info,
      query_params: conn.query_params,
      headers:
        RequestHeaders.redact(conn.req_headers, trigger.webhook_auth_methods)
    }
  end
end
