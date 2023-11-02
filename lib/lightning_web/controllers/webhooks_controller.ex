defmodule LightningWeb.WebhooksController do
  use LightningWeb, :controller

  require OpenTelemetry.Tracer

  alias Lightning.Workflows
  alias Lightning.WorkOrders

  @spec create(Plug.Conn.t(), %{path: binary()}) :: Plug.Conn.t()
  def create(conn, %{"path" => path}) do
    path = Enum.join(path, "/")
    start_opts = %{path: path}

    :telemetry.span([:lightning, :workorder, :webhook], start_opts, fn ->
      {conn, metadata} =
        OpenTelemetry.Tracer.with_span "lightning.api.webhook", %{
          attributes: start_opts
        } do
          conn = handle_create(conn)
          {conn, %{status: Plug.Conn.Status.reason_atom(conn.status)}}
        end

      {conn, start_opts |> Map.merge(metadata)}
    end)
  end

  defp handle_create(conn) do
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
