defmodule Lightning.DashboardMetrics do
  alias Lightning.Invocation.Run
  alias Lightning.Repo

  alias Lightning.WorkOrder
  import Ecto.Query

  def get_metrics(project_id) do
    %{
      work_order_metrics: get_work_order_metrics(project_id),
      run_metrics: get_run_metrics(project_id)
    }
  end

  def get_work_order_metrics(project_id) do
    thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30 * 86400, :second)
    failed_states = [:failed, :crashed, :cancelled, :killed, :exception, :lost]

    query =
      from(
        wo in WorkOrder,
        join: wf in assoc(wo, :workflow),
        where: wf.project_id == ^project_id,
        where: wo.inserted_at > ^thirty_days_ago,
        group_by: wf.project_id,
        select: %{
          total: count(wo.id),
          failed: count(wo.id) |> filter(wo.state in ^failed_states),
          failure_percentage:
            fragment(
              "ROUND(100.0 * ? / NULLIF(?, 0), 2)",
              count(wo.id) |> filter(wo.state in ^failed_states),
              count(wo.id)
            )
        }
      )

    Repo.one(query) || %{total: 0, failed: 0, failure_percentage: 0.0}
  end

  def get_run_metrics(project_id) do
    query =
      from(
        r in Run,
        join: j in assoc(r, :job),
        join: wf in assoc(j, :workflow),
        where: wf.project_id == ^project_id,
        group_by: wf.project_id,
        select: %{
          total: count(r.id),
          completed_runs:
            count(r.id) |> filter(r.exit_reason not in ["pending", "running"]),
          pending_running_runs:
            count(r.id) |> filter(r.exit_reason in ["pending", "running"]),
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

    Repo.one(query) ||
      %{
        total: 0,
        completed_runs: 0,
        pending_running_runs: 0,
        successful_runs: 0,
        success_percentage: 0.0
      }
  end
end
