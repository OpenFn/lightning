defmodule LightningWeb.API.WorkOrderRetryController do
  @moduledoc """
  `POST /api/projects/:project_id/work_orders/retries`: retries many work
  orders of a project at once, as the History page's bulk retry does, for a
  person who may run the project's workflows.

  The body selects the work orders with `filter`, the list endpoint's filters,
  worked out when the request arrives, or `work_order_ids`, at most 100, and
  may name a `job_id` to retry from instead of each work order's start. Work
  orders outside the project match nothing.
  """
  use LightningWeb, :controller

  alias Lightning.Invocation
  alias Lightning.Jobs
  alias Lightning.WorkOrders
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.HistoryBody
  alias LightningWeb.API.Request
  alias LightningWeb.API.Target

  action_fallback FallbackController

  plug LightningWeb.Plugs.AuthorizeAction, {:history, :run_workflow}

  @doc """
  Gives each selected work order a new run and answers 202 with how many were
  `enqueued` and how many `discarded`: those whose input has been wiped, whose
  workflow has been deleted, or, with a `job_id`, whose last run never reached
  the job.

  Without a `job_id` the runs are made in the background, as the History page
  makes them. A `job_id` outside the project is 422 with a `not_found` entry,
  and one whose workflow isn't every work order's a `mismatch` entry. The run
  limits are asked last, on the work orders that can be retried.

  ## Examples

      POST /api/projects/a1b2c3d4-.../work_orders/retries
      {"filter": {"state": "failed,crashed", "workflow_id": "e5f6a7b8-..."}}

      POST /api/projects/a1b2c3d4-.../work_orders/retries
      {"work_order_ids": ["c9d0e1f2-..."], "job_id": "a7b8c9d0-..."}
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
         {:ok, selection, extra} <-
           HistoryBody.selection(conn.body_params, scope, [:job_id]),
         {:ok, job} <- job(project, extra),
         work_orders =
           Invocation.search_workorders_for_retry(project, selection.search),
         :ok <- refuse_mismatch(job, work_orders),
         matched = Invocation.count_workorders(project, selection.search),
         {:ok, enqueued, _discarded} <-
           retry(work_orders, job,
             created_by: conn.assigns.current_resource,
             project_id: project.id
           ) do
      conn
      |> put_status(:accepted)
      |> json(%{enqueued: enqueued, discarded: matched - enqueued})
    end
  end

  defp job(_project, %{"job_id" => nil}), do: {:ok, nil}

  defp job(project, %{"job_id" => _} = extra) do
    with {:ok, id} <- id(extra),
         {:ok, job} <- Jobs.get_job_for_project(project.id, id) do
      {:ok, job}
    else
      {:error, :not_found} ->
        Errors.refuse([Errors.entry(["job_id"], Errors.not_visible())])

      refused ->
        refused
    end
  end

  defp job(_project, _no_job), do: {:ok, nil}

  defp id(extra) do
    case HistoryBody.id_entries(extra, "job_id") do
      [] -> Request.id({["job_id"], extra["job_id"]})
      entries -> Errors.refuse(entries)
    end
  end

  defp refuse_mismatch(nil, _work_orders), do: :ok

  defp refuse_mismatch(job, work_orders) do
    if Enum.all?(work_orders, &(&1.workflow_id == job.workflow_id)),
      do: :ok,
      else:
        Errors.refuse([
          Errors.entry(
            ["job_id"],
            {"is not in the workflow of every work order", code: :mismatch}
          )
        ])
  end

  defp retry([], _job, _opts), do: {:ok, 0, 0}

  defp retry(work_orders, nil, opts),
    do: WorkOrders.retry_many(work_orders, opts)

  defp retry(work_orders, job, opts),
    do: WorkOrders.retry_many(work_orders, job.id, opts)
end
