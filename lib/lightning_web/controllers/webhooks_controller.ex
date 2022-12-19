defmodule LightningWeb.WebhooksController do
  use LightningWeb, :controller

  alias Lightning.{Jobs, WorkOrderService}

  @spec create(Plug.Conn.t(), %{path: binary()}) :: Plug.Conn.t()
  def create(conn, %{"path" => path}) do
    path
    |> Enum.join("/")
    |> Jobs.get_job_by_webhook()
    |> case do
      nil ->
        put_status(conn, :not_found)
        |> json(%{})

      %Jobs.Job{enabled: false} ->
        put_status(conn, :forbidden)
        |> json(%{
          message:
            "Unable to process request, trigger is disabled. Enable it on OpenFn to allow requests to this endpoint."
        })

      job ->
        {:ok, %{work_order: work_order, attempt_run: attempt_run}} =
          WorkOrderService.create_webhook_workorder(job, conn.body_params)

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
