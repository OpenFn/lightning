defmodule LightningWeb.WebhooksController do
  use LightningWeb, :controller

  alias Lightning.Extensions.RateLimiting
  alias Lightning.Extensions.UsageLimiting.Action
  alias Lightning.Extensions.UsageLimiting.Context
  alias Lightning.Services.RateLimiter
  alias Lightning.Services.UsageLimiter
  alias Lightning.Workflows
  alias Lightning.WorkOrders

  require OpenTelemetry.Tracer

  @spec create(Plug.Conn.t(), %{path: binary()}) :: Plug.Conn.t()
  def create(conn, _params) do
    with %Workflows.Trigger{enabled: true, workflow: %{project_id: project_id}} =
           trigger <- conn.assigns.trigger,
         {:ok, without_run?} <- check_action_limit(project_id),
         :ok <-
           RateLimiter.limit_request(
             conn,
             %RateLimiting.Context{project_id: project_id},
             []
           ) do
      {:ok, work_order} =
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

      conn |> json(%{work_order_id: work_order.id})
    else
      {:error, reason, %{text: message}} ->
        status =
          if reason == :too_many_requests,
            do: :too_many_requests,
            else: :payment_required

        conn
        |> put_status(status)
        |> json(%{"error" => message})

      nil ->
        conn
        |> put_status(:not_found)
        |> json(%{"error" => "Webhook not found"})

      _disabled ->
        put_status(conn, :forbidden)
        |> json(%{
          message:
            "Unable to process request, trigger is disabled. Enable it on OpenFn to allow requests to this endpoint."
        })
    end
  end

  defp check_action_limit(project_id) do
    case UsageLimiter.limit_action(
           %Action{type: :new_run},
           %Context{project_id: project_id}
         ) do
      :ok ->
        {:ok, false}

      {:error, :too_many_runs, _message} ->
        {:ok, true}

      error -> error
    end
  end

  defp build_request(%Plug.Conn{} = conn) do
    %{headers: conn.req_headers |> Enum.into(%{})}
  end
end
