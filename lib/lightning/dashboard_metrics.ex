defmodule Lightning.DashboardMetrics do
  @moduledoc false

  alias Lightning.Projects.Project
  alias Lightning.Invocation.Run
  alias Lightning.Repo

  import Ecto.Query

  def get_metrics(%Project{id: project_id}, workflows) do
    %{
      work_order_metrics: get_work_order_metrics(workflows),
      run_metrics: get_run_metrics(project_id)
    }
  end

  defp get_work_order_metrics(workflows) do
    Enum.reduce(workflows, %{total: 0, failed: 0}, fn %{
                                                        workorders_count:
                                                          workorders_count
                                                      },
                                                      %{
                                                        total: acc_total,
                                                        failed: acc_failed
                                                      } ->
      success = Map.get(workorders_count, :success, 0)
      failed = Map.get(workorders_count, :failed, 0)
      unfinished = Map.get(workorders_count, :unfinished, 0)

      total = success + failed + unfinished

      %{
        total: acc_total + total,
        failed: acc_failed + failed
      }
    end)
    |> then(fn %{total: total, failed: failed} = map ->
      failure_rate = if total > 0, do: failed / total * 100, else: 0.0

      Map.put(map, :failure_percentage, failure_rate)
    end)
  end

  defp get_run_metrics(project_id) do
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
