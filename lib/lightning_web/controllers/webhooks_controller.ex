defmodule LightningWeb.WebhooksController do
  use LightningWeb, :controller

  alias Lightning.Workflows
  alias Lightning.WorkOrders

  require OpenTelemetry.Tracer

  @spec create(Plug.Conn.t(), %{path: binary()}) :: Plug.Conn.t()
  def create(conn, params) do
    File.write!(
      "webhook_params.txt",
      "params length: #{String.length(params["txt"])}"
    )

    case conn.assigns.trigger do
      nil ->
        conn |> put_status(:not_found) |> json(%{"error" => "Webhook not found"})

      %Workflows.Trigger{enabled: true} = trigger ->
        {:ok, work_order} =
          WorkOrders.create_for(trigger,
            workflow: trigger.workflow,
            dataclip: %{
              body: conn.body_params,
              type: :http_request,
              project_id: trigger.workflow.project_id
            }
          )

        conn |> json(%{work_order_id: work_order.id})

      _disabled ->
        put_status(conn, :forbidden)
        |> json(%{
          message:
            "Unable to process request, trigger is disabled. Enable it on OpenFn to allow requests to this endpoint."
        })
    end
  end
end
