defmodule LightningWeb.WebhooksController do
  use LightningWeb, :controller

  alias Lightning.{Jobs, WorkOrderService, Workflows}

  @spec create(Plug.Conn.t(), %{path: binary()}) :: Plug.Conn.t()
  def create(conn, %{"path" => path}) do
    path
    |> Enum.join("/")
    |> Jobs.get_edge_by_webhook()
    |> case do
      nil ->
        put_status(conn, :not_found)
        |> json(%{})

      %Workflows.Edge{target_job: %Jobs.Job{enabled: false}} ->
        put_status(conn, :forbidden)
        |> json(%{
          message:
            "Unable to process request, trigger is disabled. Enable it on OpenFn to allow requests to this endpoint."
        })

      %Workflows.Edge{target_job: job, source_trigger: trigger} ->
        {:ok, %{work_order: work_order, attempt_run: attempt_run}} =
          WorkOrderService.create_webhook_workorder(
            job,
            trigger,
            conn.body_params
          )

        resp = %{
          work_order_id: work_order.id,
          run_id: attempt_run.run_id,
          attempt_id: attempt_run.attempt_id
        }

        conn
        |> json(resp)
    end
  end
end
