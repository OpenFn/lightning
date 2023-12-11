defmodule Lightning.DashboardMetrics do
  alias Lightning.Invocation.Run
  alias Lightning.Repo
  alias Lightning.Workflows.Workflow

  alias Lightning.WorkOrder
  import Ecto.Query

  def get_metrics(project_id) do
    # We could assume scheduled way to calculate these values
    total_workorders = total_work_orders_in_last_30_days(project_id)
    total_runs = aggregate_runs_for_project(project_id)
    successful_runs = calculate_successful_runs_and_percentage(project_id)
    failed_workorders = calculate_failed_work_orders_and_percentage(project_id)

    [
      total_workorders: total_workorders,
      total_runs: total_runs,
      successful_runs: successful_runs,
      failed_workorders: failed_workorders
    ]
  end

  def total_work_orders_in_last_30_days(project_id) do
    thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30 * 86400, :second)

    count_query =
      from(
        wo in WorkOrder,
        join: wf in Workflow,
        on: wf.id == wo.workflow_id,
        where: wf.project_id == ^project_id,
        where: wo.inserted_at > ^thirty_days_ago,
        select: count(wo.id)
      )

    Repo.one(count_query) || 0
  end

  def aggregate_runs_for_project(project_id) do
    query =
      from(
        r in Run,
        join: j in assoc(r, :job),
        join: wf in assoc(j, :workflow),
        where: wf.project_id == ^project_id,
        select: %{
          completed_runs:
            count(r.id) |> filter(r.exit_reason not in ["pending", "running"]),
          pending_running_runs:
            count(r.id) |> filter(r.exit_reason in ["pending", "running"])
        }
      )

    Repo.one(query) || %{completed_runs: 0, pending_running_runs: 0}
  end

  def calculate_successful_runs_and_percentage(project_id) do
    query =
      from(
        r in Run,
        join: j in assoc(r, :job),
        join: wf in assoc(j, :workflow),
        where: wf.project_id == ^project_id,
        select: %{
          successful_runs:
            count(
              fragment(
                "CASE WHEN ? = 'success' THEN 1 ELSE NULL END",
                r.exit_reason
              )
            ),
          success_percentage:
            fragment(
              "COALESCE(ROUND(100.0 * COUNT(CASE WHEN ? = 'success' THEN 1 ELSE NULL END) / NULLIF(COUNT(*), 0), 2), 0)",
              r.exit_reason
            )
        }
      )

    Repo.one(query) || %{successful_runs: 0, success_percentage: 0.0}
  end

  def calculate_failed_work_orders_and_percentage(project_id) do
    failed_states = [:failed, :crashed, :cancelled, :killed, :exception, :lost]

    # Subquery for counting failed work orders
    failed_subquery =
      from(
        wo in WorkOrder,
        join: wf in assoc(wo, :workflow),
        where: wf.project_id == ^project_id and wo.state in ^failed_states,
        select: count(wo.id)
      )

    # Main query for total work orders and calculating percentage
    main_query =
      from(
        wo in WorkOrder,
        join: wf in assoc(wo, :workflow),
        where: wf.project_id == ^project_id,
        select: %{
          failed_workorders: subquery(failed_subquery),
          failure_percentage:
            fragment(
              "COALESCE(ROUND(? * 100.0 / NULLIF(?, 0), 2), 0)",
              subquery(failed_subquery),
              count(wo.id)
            )
        }
      )

    Repo.one(main_query) || %{failed_workorders: 0, failure_percentage: 0.0}
  end
end
