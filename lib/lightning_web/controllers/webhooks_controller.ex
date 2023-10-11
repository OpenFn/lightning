defmodule LightningWeb.WebhooksController do
  use LightningWeb, :controller

  require OpenTelemetry.Tracer

  alias Lightning.{Workflows, WorkOrderService, Jobs}

  # this gets hit when someone asks to run a workflow by API
  @spec create(Plug.Conn.t(), %{path: binary()}) :: Plug.Conn.t()
  def create(conn, %{"path" => path}) do
    source_trigger_id = path |> List.last()

    :telemetry.span(
      [:lightning, :workorder, :webhook],
      %{source_trigger_id: source_trigger_id},
      fn ->
        {result, metadata} =
          OpenTelemetry.Tracer.with_span "lightning.api.webhook",
                                         %{
                                           attributes: %{
                                             source_trigger_id: source_trigger_id
                                           }
                                         } do
            path
            |> Enum.join("/")
            |> Workflows.get_edge_by_webhook()
            |> case do
              nil ->
                {
                  put_status(conn, :not_found) |> json(%{}),
                  %{status: :not_found}
                }

              %Workflows.Edge{target_job: %Jobs.Job{enabled: false}} ->
                {
                  put_status(conn, :forbidden)
                  |> json(%{
                    message:
                      "Unable to process request, trigger is disabled. Enable it on OpenFn to allow requests to this endpoint."
                  }),
                  %{status: :forbidden}
                }

              edge ->
                {:ok, %{work_order: work_order, attempt_run: attempt_run}} =
                  WorkOrderService.create_webhook_workorder(
                    edge,
                    conn.body_params
                  )

                resp = %{
                  work_order_id: work_order.id,
                  run_id: attempt_run.run_id,
                  attempt_id: attempt_run.attempt_id
                }

                {
                  conn |> json(resp),
                  %{status: :ok}
                }
            end
          end

        {
          result,
          %{source_trigger_id: source_trigger_id} |> Map.merge(metadata)
        }
      end
    )
  end
end
