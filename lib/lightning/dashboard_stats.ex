defmodule Lightning.DashboardStats do
  @moduledoc false

  alias Lightning.Projects.Project
  alias Lightning.Invocation.Run
  alias Lightning.Repo
  alias Lightning.Workflows.Workflow

  import Ecto.Query

  defmodule WorkflowStats do
    defstruct last_workorder: nil,
              grouped_runs_count: %{},
              grouped_workorders_count: %{},
              workflow: %Workflow{}
  end

  defmodule ProjectMetrics do
    defstruct work_order_metrics: %{
                total: 0,
                failed: 0,
                failure_percentage: 0.0
              },
              run_metrics: %{
                total: 0,
                completed: 0,
                pending: 0,
                success: 0,
                success_percentage: 0.0
              }
  end

  def get_stats_per_workflow(%Project{id: project_id}) do
    from(w in Workflow,
      preload: [:triggers],
      where: w.project_id == ^project_id,
      order_by: [asc: w.name]
    )
    |> Repo.all()
    |> Enum.map(fn workflow ->
      %WorkflowStats{
        workflow: workflow,
        last_workorder: get_last_workorder(workflow),
        grouped_runs_count: count_runs(workflow),
        grouped_workorders_count: count_workorders(workflow)
      }
    end)
  end

  def aggregate_project_metrics(workflows_stats) do
    %ProjectMetrics{
      work_order_metrics: aggregate_work_order_metrics(workflows_stats),
      run_metrics: aggregate_run_metrics(workflows_stats)
    }
  end

  defp get_last_workorder(%Workflow{id: workflow_id}) do
    thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30 * 24 * 60 * 60)

    from(wo in Lightning.WorkOrder,
      where: wo.workflow_id == ^workflow_id,
      where: wo.inserted_at > ^thirty_days_ago,
      where: wo.state not in [:pending, :running],
      order_by: [desc: wo.inserted_at],
      select: %{state: wo.state, updated_at: wo.inserted_at}
    )
    |> limit(1)
    |> Repo.one()
  end

  defp count_workorders(%Workflow{id: workflow_id}) do
    thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30 * 24 * 60 * 60)

    from(wo in Lightning.WorkOrder,
      where: wo.workflow_id == ^workflow_id,
      where: wo.inserted_at > ^thirty_days_ago,
      select: wo.state
    )
    |> Repo.all()
    |> Enum.group_by(fn state ->
      cond do
        state == :success ->
          :success

        state in [:pending, :running] ->
          :unfinished

        true ->
          :failed
      end
    end)
    |> Map.new(fn {state, list} -> {state, length(list)} end)
  end

  defp count_runs(%Workflow{id: workflow_id}) do
    thirty_days_ago = DateTime.utc_now() |> DateTime.add(-30 * 24 * 60 * 60)

    from(r in Run,
      join: j in assoc(r, :job),
      join: wf in assoc(j, :workflow),
      where: wf.id == ^workflow_id,
      where: r.inserted_at > ^thirty_days_ago,
      select: %{
        exit_reason: r.exit_reason
      }
    )
    |> Repo.all()
    |> Enum.group_by(fn %{exit_reason: exit_reason} ->
      cond do
        exit_reason == :success -> :success
        exit_reason == nil -> :pending
        true -> :failed
      end
    end)
    |> Map.new(fn {state, list} -> {state, length(list)} end)
  end

  defp aggregate_work_order_metrics(workflows) do
    Enum.reduce(workflows, %{total: 0, failed: 0}, fn %{
                                                        grouped_workorders_count:
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

  defp aggregate_run_metrics(workflows) do
    Enum.reduce(workflows, %{success: 0, failed: 0, pending: 0}, fn %{
                                                                      grouped_runs_count:
                                                                        runs_count
                                                                    },
                                                                    %{
                                                                      success:
                                                                        acc_success,
                                                                      failed:
                                                                        acc_failed,
                                                                      pending:
                                                                        acc_pending
                                                                    } ->
      success = Map.get(runs_count, :success, 0)
      failed = Map.get(runs_count, :failed, 0)
      pending = Map.get(runs_count, :pending, 0)

      %{
        success: acc_success + success,
        failed: acc_failed + failed,
        pending: acc_pending + pending
      }
    end)
    |> then(fn %{success: success, failed: failed, pending: pending} = map ->
      completed = success + failed
      total = completed + pending
      success_rate = if success > 0, do: failed / success * 100, else: 0.0

      Map.merge(map, %{
        completed: completed,
        success_percentage: success_rate,
        total: total
      })
    end)
  end
end
