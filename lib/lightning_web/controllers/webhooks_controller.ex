defmodule LightningWeb.WebhooksController do
  use LightningWeb, :controller

  alias Lightning.{Workflows, WorkOrders}

  # this gets hit when someone asks to run a workflow by API
  @spec create(Plug.Conn.t(), %{path: binary()}) :: Plug.Conn.t()
  def create(conn, %{"path" => path}) do
    path
    |> Enum.join("/")
    |> Workflows.get_webhook_trigger(include: [:workflow, :edges])
    |> case do
      nil ->
        put_status(conn, :not_found)
        |> json(%{})

      %Workflows.Edge{target_job: %Workflows.Job{enabled: false}} ->
        put_status(conn, :forbidden)
        |> json(%{
          message:
            "Unable to process request, trigger is disabled. Enable it on OpenFn to allow requests to this endpoint."
        })

      trigger ->
        {:ok, work_order} =
          WorkOrders.create_for(trigger,
            workflow: trigger.workflow,
            dataclip: %{
              body: conn.body_params,
              type: :http_request,
              project_id: trigger.workflow.project_id
            }
          )

        conn
        |> json(%{work_order_id: work_order.id})
    end
  end
end
