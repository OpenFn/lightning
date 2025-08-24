defmodule LightningWeb.WebhooksController do
  use LightningWeb, :controller

  alias Lightning.Config
  alias Lightning.Extensions.RateLimiting
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Retry
  alias Lightning.Services.RateLimiter
  alias Lightning.Services.UsageLimiter
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
          json(conn, %{work_order_id: work_order.id})

        {:error, %DBConnection.ConnectionError{} = error} ->
          retry_after =
            Config.webhook_retry(:timeout_ms)
            |> div(1000)
            |> max(1)

          Logger.error(
            "webhook create_workorder exhausted retries " <>
              "trigger_id=#{trigger.id} workflow_id=#{trigger.workflow.id} " <>
              "project_id=#{project_id} error=#{Exception.message(error)}"
          )

          conn
          |> put_resp_header("retry-after", Integer.to_string(retry_after))
          |> put_status(:service_unavailable)
          |> json(%{
            error: :service_unavailable,
            message:
              "Unable to process request due to temporary database issues. Please try again in #{retry_after}s.",
            retry_after: retry_after
          })

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
        |> json(%{error: :webhook_not_found})

      _disabled ->
        put_status(conn, :forbidden)
        |> json(%{
          error: :trigger_disabled,
          message:
            "Unable to process request, trigger is disabled. Enable it on OpenFn to allow requests to this endpoint."
        })
    end
  end

  defp check_skip_run_creation(project_id) do
    case UsageLimiter.limit_action(
           %Action{type: :new_run},
           %Context{project_id: project_id}
         ) do
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
