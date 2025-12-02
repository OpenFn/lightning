defmodule LightningWeb.WebhooksController do
  use LightningWeb, :controller

  alias Lightning.Extensions.RateLimiting
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
         {:ok, without_run?} <- check_skip_run_creation(project_id),
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
              request: build_request(conn),
              type: :http_request,
              project_id: project_id
            },
            without_run: without_run?
          )
        end,
        retry_on: &Retry.retriable_error?/1,
        context: %{trigger_id: trigger.id, workflow_id: trigger.workflow.id}
      )
      |> case do
        {:ok, work_order} ->
          if trigger.webhook_reply != :before_start do
            handle_delayed_response(conn, work_order)
          else
            json(conn, %{work_order_id: work_order.id})
          end

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
        status =
          if reason == :too_many_requests,
            do: :too_many_requests,
            else: :payment_required

        conn
        |> put_status(status)
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

  defp handle_delayed_response(conn, work_order) do
    topic = "work_order:#{work_order.id}:webhook_response"
    Phoenix.PubSub.subscribe(Lightning.PubSub, topic)

    receive do
      {:webhook_response, status_code, body} ->
        conn
        |> put_status(status_code)
        |> json(body)

      {:webhook_error, status_code, error} ->
        conn
        |> put_status(status_code)
        |> json(%{error: error})
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

  defp check_skip_run_creation(project_id) do
    case WorkOrders.limit_run_creation(project_id) do
      :ok ->
        {:ok, false}

      {:error, :too_many_runs, _message} ->
        {:ok, true}

      error ->
        error
    end
  end

  defp build_request(%Plug.Conn{} = conn) do
    %{
      method: conn.method,
      path: conn.path_info,
      query_params: conn.query_params,
      headers: conn.req_headers |> Enum.into(%{})
    }
  end
end
