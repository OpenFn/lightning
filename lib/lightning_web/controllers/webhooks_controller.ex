defmodule LightningWeb.WebhooksController do
  use LightningWeb, :controller

  alias Lightning.Extensions.Message
  alias Lightning.Extensions.RateLimiting
  alias Lightning.Invocation.RequestHeaders
  alias Lightning.Retry
  alias Lightning.Services.RateLimiter
  alias Lightning.Workflows
  alias Lightning.WorkOrders
  alias LightningWeb.API.Codes
  alias LightningWeb.API.Errors
  alias LightningWeb.API.Problem

  require Logger

  plug :reject_unfetched when action in [:create]

  defp reject_unfetched(conn, _) do
    case conn.body_params do
      %Plug.Conn.Unfetched{} ->
        Problem.halt(conn, Problem.new(:unsupported_media_type))

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
            halt?: false
          )

        # The work order is built from the trigger and the workflow, not shaped
        # by the request, so its errors have no place in the body to point at
        # and the walker would raise on them. The body as a whole is what could
        # not be saved, at 422 as /i/* always answered (spec §12).
        {:error, reason}
        when is_atom(reason) or is_struct(reason, Ecto.Changeset) ->
          entry = Errors.entry([], {"is invalid", code: :invalid})
          Problem.respond(conn, Problem.new(:invalid, errors: [entry]))
      end
    else
      {:error, reason, %Message{}} ->
        Problem.respond(conn, limited(reason))

      nil ->
        Problem.respond(conn, Problem.new(:not_found))

      _disabled ->
        Problem.respond(conn, Problem.new(:trigger_disabled))
    end
  end

  # Every limiter refusal on /i/* is a 429, whatever the reason, and an unknown
  # project's is `exceeds_limit` where the API's is 404 (spec §12).
  defp limited(reason, opts \\ [])

  defp limited(:unknown_project, opts), do: limited(:exceeds_limit, opts)

  defp limited(reason, opts),
    do: Problem.new(Codes.for_limiter(reason), [status: 429] ++ opts)

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

  # The one success body that carries `error`: the payload was saved, so a 4xx
  # would make senders resend it (spec §10).
  defp rejection_details(nil), do: %{}
  defp rejection_details({reason, %Message{}}), do: %{error: reason}

  defp has_run?(%{runs: [_ | _]}), do: true
  defp has_run?(_work_order), do: false

  # A synchronous request whose work order carries no run can never be answered
  # by a completion broadcast, so reply now with the reason the run was not
  # created rather than holding the connection open for the full timeout.
  defp respond_without_run(conn, work_order, run_rejection) do
    extensions = %{work_order_id: work_order.id}

    problem =
      case run_rejection do
        {reason, _message} ->
          limited(reason, extensions: extensions)

        nil ->
          Logger.warning(
            "Synchronous webhook work order created without a run: " <>
              inspect(work_order.id)
          )

          Problem.new(:internal, extensions: extensions)
      end

    Problem.respond(conn, problem)
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

        Problem.respond(
          conn,
          Problem.new(:timeout, extensions: %{work_order_id: work_order.id})
        )
    end
  end

  # `{:error, :too_many_runs, _}` is not fatal: the payload is still recorded as
  # a rejected work order, just without a run. The refusal travels with that
  # decision instead of being collapsed into a bare boolean, so the response can
  # say why no run was created, and when to try again.
  defp check_skip_run_creation(project_id) do
    case WorkOrders.limit_run_creation(project_id) do
      :ok ->
        {:ok, nil}

      {:error, :too_many_runs, message} ->
        {:ok, {:too_many_runs, message}}

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
