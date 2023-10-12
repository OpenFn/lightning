defmodule LightningWeb.WebhooksController do
  use LightningWeb, :controller

  alias Lightning.{Workflows, WorkOrderService, Jobs}

  # this gets hit when someone asks to run a workflow by API
  @spec create(Plug.Conn.t(), %{path: binary()}) :: Plug.Conn.t()
  def create(conn, %{"path" => _path}) do
    :telemetry.span(
      [:lightning, :workorder, :webhook],
      %{source_trigger_id: source_trigger_id},
      fn ->
        conn.assigns[:trigger]
        |> Workflows.get_edge_by_trigger()
        |> case do
          %Workflows.Edge{target_job: %Jobs.Job{enabled: false}} ->
            put_status(conn, :forbidden)
            |> json(%{
              message:
                "Unable to process request, trigger is disabled. Enable it on OpenFn to allow requests to this endpoint."
            })

          edge ->
            {:ok, %{work_order: work_order, attempt_run: attempt_run}} =
              WorkOrderService.create_webhook_workorder(edge, conn.body_params)

            resp = %{
              work_order_id: work_order.id,
              run_id: attempt_run.run_id,
              attempt_id: attempt_run.attempt_id
            }

            conn
            |> json(resp)
        end
      end
    )
  end
end
