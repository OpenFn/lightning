defmodule LightningWeb.WebhooksController do
  use LightningWeb, :controller

  alias Lightning.{Workflows, WorkOrderService}

  # this gets hit when someone asks to run a workflow by API
  @spec create(Plug.Conn.t(), %{path: binary()}) :: Plug.Conn.t()
  def create(conn, %{"path" => path}) do
    path
    |> Enum.join("/")
    # TODO - this thing returns a job VIA the edge from { THIS_TRIGGER, to, THAT_JOB }
    |> Workflows.get_edge_by_webhook()
    |> case do
      nil ->
        put_status(conn, :not_found)
        |> json(%{})

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
end
