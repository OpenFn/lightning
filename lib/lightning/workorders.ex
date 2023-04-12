defmodule Lightning.Workorders do
  @moduledoc false
  import Ecto.Query, warn: false

  alias Lightning.WorkOrderService
  alias Lightning.WorkOrder
  alias Lightning.Projects
  alias Lightning.Repo

  @doc """
  Get a map of counts for successful, rerun and failed Workorders for a given
  digest.
  """
  def get_digest_data(workflow, digest)
      when digest in [:daily, :weekly, :monthly] do
    date_after = digest_to_date(digest)
    successful_workorders = successful_workorders(workflow, date_after)
    failed_workorders = failed_workorders(workflow, date_after)
    rerun_workorders = rerun_workorders(workflow, date_after)

    %{
      workflow_name: workflow.name,
      successful_workorders: successful_workorders.total_entries,
      rerun_workorders: rerun_workorders.total_entries,
      failed_workorders: failed_workorders.total_entries
    }
  end

  defp digest_to_date(digest) do
    case digest do
      :monthly ->
        Timex.now() |> Timex.shift(months: -1) |> Timex.beginning_of_month()

      :daily ->
        Timex.now() |> Timex.beginning_of_day()

      :weekly ->
        Timex.now() |> Timex.shift(days: -7) |> Timex.beginning_of_week()
    end
  end

  defp successful_workorders(workflow, date_after) do
    Lightning.Invocation.list_work_orders_for_project(
      Projects.get_project!(workflow.project_id),
      [
        status: [:success],
        search_fields: [:body, :log],
        search_term: "",
        workflow_id: workflow.id,
        date_after: date_after,
        date_before: Timex.now(),
        wo_date_after: "",
        wo_date_before: ""
      ],
      %{}
    )
  end

  defp failed_workorders(workflow, date_after) do
    Lightning.Invocation.list_work_orders_for_project(
      Projects.get_project!(workflow.project_id),
      [
        status: [:failure],
        search_fields: [:body, :log],
        search_term: "",
        workflow_id: workflow.id,
        date_after: date_after,
        date_before: Timex.now(),
        wo_date_after: "",
        wo_date_before: ""
      ],
      %{}
    )
  end

  defp rerun_workorders(workflow, date_after) do
    from(wo in Lightning.WorkOrder,
      join: a in Lightning.Attempt,
      on: wo.id == a.work_order_id,
      as: :attempt,
      join: ar in Lightning.AttemptRun,
      on: a.id == ar.attempt_id,
      join: r in Lightning.Invocation.Run,
      on: ar.run_id == r.id,
      where:
        wo.workflow_id == ^workflow.id and r.exit_code != 0 and
          r.finished_at >= ^date_after and
          exists(
            from(ar2 in Lightning.AttemptRun,
              join: r2 in Lightning.Invocation.Run,
              on: ar2.run_id == r2.id,
              where:
                parent_as(:attempt).id == ar2.attempt_id and
                  r2.exit_code == 0 and
                  r2.finished_at >= ^date_after,
              order_by: [desc: r2.inserted_at],
              limit: 1,
              offset: 0,
              select: 1
            )
          ),
      distinct: true,
      select: wo
    )
    |> Repo.paginate(%{})
  end
end
