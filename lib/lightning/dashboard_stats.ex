defmodule Lightning.DashboardStats do
  @moduledoc false

  alias Lightning.Invocation.Run
  alias Lightning.Repo
  alias Lightning.Workflows.Workflow

  import Ecto.Query

  defmodule WorkflowStats do
    defstruct last_workorder: %{state: nil, updated_at: nil},
              last_failed_workorder: %{state: nil, updated_at: nil},
              failed_workorders_count: 0,
              grouped_runs_count: %{},
              grouped_workorders_count: %{},
              runs_count: 0,
              runs_success_percentage: 0.0,
              workorders_count: 0,
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
                pending: 0,
                success: 0,
                success_percentage: 0.0
              }
  end

  def get_workflow_stats(%Workflow{} = workflow) do
    %{failed: failed_wo_count} =
      grouped_workorders_count = count_workorders(workflow)

    %{success: success_runs_count} =
      grouped_runs_count = count_runs(workflow)

    runs_count =
      grouped_runs_count
      |> Enum.map(fn {_key, count} -> count end)
      |> Enum.sum()

    workorders_count =
      grouped_workorders_count
      |> Enum.map(fn {_key, count} -> count end)
      |> Enum.sum()

    runs_success_percentage =
      if runs_count == 0, do: 0, else: success_runs_count * 100 / runs_count

    last_workorder = get_last_workorder(workflow)

    %WorkflowStats{
      workflow: workflow,
      last_workorder: last_workorder,
      last_failed_workorder: get_last_failed_workorder(workflow, last_workorder),
      failed_workorders_count: failed_wo_count,
      grouped_runs_count: grouped_runs_count,
      grouped_workorders_count: grouped_workorders_count,
      runs_count: runs_count,
      runs_success_percentage: round(runs_success_percentage * 100) / 100,
      workorders_count: workorders_count
    }
  end

  def aggregate_project_metrics(workflows_stats) do
    %ProjectMetrics{
      work_order_metrics: aggregate_work_order_metrics(workflows_stats),
      run_metrics: aggregate_run_metrics(workflows_stats)
    }
  end

  defp get_last_failed_workorder(workflow, %{state: :success}) do
    excluded_states = [:pending, :running, :success]
    get_last_workorder(workflow, excluded_states)
  end

  defp get_last_failed_workorder(_workflow, %{state: _other} = failed_wo) do
    failed_wo
  end

  defp get_last_workorder(
         %Workflow{id: workflow_id},
         excluded_states \\ [:pending, :running]
       ) do
    from(wo in Lightning.WorkOrder,
      where: wo.workflow_id == ^workflow_id,
      where: wo.state not in ^excluded_states,
      order_by: [desc: wo.inserted_at],
      select: %{state: wo.state, updated_at: wo.updated_at}
    )
    |> limit(1)
    |> Repo.one() ||
      %{state: nil, updated_at: nil}
  end

  defp count_workorders(%Workflow{id: workflow_id}) do
    from(wo in Lightning.WorkOrder,
      where: wo.workflow_id == ^workflow_id,
      select: wo.state
    )
    |> filter_days_ago(30)
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
    |> Enum.into(%{success: 0, failed: 0, unfinished: 0}, fn {state, list} ->
      {state, length(list)}
    end)
  end

  defp count_runs(%Workflow{id: workflow_id}) do
    from(r in Run,
      join: j in assoc(r, :job),
      join: wf in assoc(j, :workflow),
      where: wf.id == ^workflow_id,
      select: r.exit_reason
    )
    |> filter_days_ago(30)
    |> Repo.all()
    |> Enum.group_by(fn exit_reason ->
      cond do
        exit_reason == "success" -> :success
        exit_reason == nil -> :pending
        true -> :failed
      end
    end)
    |> Enum.into(%{success: 0, failed: 0, pending: 0}, fn {state, list} ->
      {state, length(list)}
    end)
  end

  defp aggregate_work_order_metrics(workflows) do
    Enum.reduce(workflows, %{total: 0, failed: 0}, fn %{
                                                        grouped_workorders_count:
                                                          %{
                                                            success: success,
                                                            failed: failed,
                                                            unfinished:
                                                              unfinished
                                                          }
                                                      },
                                                      %{
                                                        total: acc_total,
                                                        failed: acc_failed
                                                      } ->
      total = success + failed + unfinished

      %{
        total: acc_total + total,
        failed: acc_failed + failed
      }
    end)
    |> then(fn %{total: total, failed: failed} = map ->
      failure_rate = if total > 0, do: failed / total * 100, else: 0.0

      Map.put(map, :failure_percentage, round(failure_rate * 100) / 100)
    end)
  end

  defp aggregate_run_metrics(workflows) do
    Enum.reduce(workflows, %{success: 0, failed: 0, pending: 0}, fn %{
                                                                      grouped_runs_count:
                                                                        %{
                                                                          success:
                                                                            success,
                                                                          failed:
                                                                            failed,
                                                                          pending:
                                                                            pending
                                                                        }
                                                                    },
                                                                    %{
                                                                      success:
                                                                        acc_success,
                                                                      failed:
                                                                        acc_failed,
                                                                      pending:
                                                                        acc_pending
                                                                    } ->
      %{
        success: acc_success + success,
        failed: acc_failed + failed,
        pending: acc_pending + pending
      }
    end)
    |> then(fn %{success: success, failed: failed, pending: pending} = map ->
      completed = success + failed
      success_rate = if success > 0, do: success * 100 / completed, else: 0.0

      Map.merge(map, %{
        success_percentage: round(success_rate * 100) / 100,
        total: completed + pending
      })
    end)
  end

  def filter_days_ago(query, days) do
    days_ago = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60)

    query
    |> where([r], r.inserted_at > ^days_ago)
  end
end
