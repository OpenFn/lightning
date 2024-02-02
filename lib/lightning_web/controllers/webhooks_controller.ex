defmodule LightningWeb.WebhooksController do
  use LightningWeb, :controller

  alias Lightning.Extensions.RateLimiter
  alias Lightning.Extensions.RateLimiting.Context
  alias Lightning.Workflows
  alias Lightning.WorkOrders

  require OpenTelemetry.Tracer

  @spec create(Plug.Conn.t(), %{path: binary()}) :: Plug.Conn.t()
  def create(conn, _params) do
    with %Workflows.Trigger{enabled: true, workflow: %{project_id: project_id}} =
           trigger <- conn.assigns.trigger,
         :ok <-
           RateLimiter.limit_request(conn, %Context{project_id: project_id}, []) do
      {:ok, work_order} =
        WorkOrders.create_for(trigger,
          workflow: trigger.workflow,
          dataclip: %{
            body: conn.body_params,
            request: build_request(conn),
            type: :http_request,
            project_id: project_id
          }
        )

      conn |> json(%{work_order_id: work_order.id})
    else
      {:error, _reason, message} ->
        conn
        |> put_status(:too_many_requests)
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

  defp build_request(%Plug.Conn{} = conn) do
    %{headers: conn.req_headers |> Enum.into(%{})}
  end
end
