defmodule LightningWeb.API.WorkOrderCancellationController do
  @moduledoc """
  `POST /api/projects/:project_id/work_orders/cancellations`: cancels the runs
  no worker has claimed yet across many work orders of a project, as the
  History page's bulk cancel does, for a person who may run the project's
  workflows.

  The body selects the work orders as for retrying many: `filter` or
  `work_order_ids`.
  """
  use LightningWeb, :controller

  alias Lightning.Invocation
  alias Lightning.WorkOrders
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.HistoryBody
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target

  action_fallback FallbackController

  plug LightningWeb.Plugs.AuthorizeAction, {:history, :run_workflow}

  @doc """
  Answers 202 with `cancelled`, the number of selected work orders that had a
  run no worker had claimed. Work orders listed by id are cancelled in the
  request; a filter's are cancelled in the background, in batches of 100
  runs.

  ## Examples

      POST /api/projects/a1b2c3d4-.../work_orders/cancellations
      {"work_order_ids": ["c9d0e1f2-...", "a7b8c9d0-..."]}
  """
  @spec create(Plug.Conn.t(), map()) :: Plug.Conn.t() | {:error, term()}
  def create(conn, _params) do
    scope = conn.assigns.scope

    with {:ok, project} <-
           Target.project(
             scope,
             Request.param(conn, "project_id"),
             {:history, :run_workflow}
           ),
         {:ok, selection, _extra} <-
           HistoryBody.selection(conn.body_params, scope, []),
         work_orders =
           Invocation.search_workorders_for_cancel(project, selection.search),
         :ok <- cancel(work_orders, selection.by_id?, project.id) do
      conn
      |> put_status(:accepted)
      |> json(%{cancelled: length(work_orders)})
    end
  end

  defp cancel([], _by_id?, _project_id), do: :ok

  defp cancel(work_orders, true, project_id) do
    with {:ok, _runs} <-
           WorkOrders.cancel_many(work_orders, project_id: project_id),
         do: :ok
  end

  defp cancel(work_orders, false, project_id) do
    with {:ok, _job} <-
           WorkOrders.cancel_many_async(work_orders, project_id: project_id),
         do: :ok
  end
end
