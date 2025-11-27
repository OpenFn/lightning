defmodule Lightning.DashboardStats do
  @moduledoc """
  Dashboard stats for a project and its workflows.
  """

  import Ecto.Query

  alias Lightning.Invocation.Step
  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.Workflows.Workflow
  alias Lightning.WorkOrder

  defmodule WorkflowStats do
    @moduledoc """
    Stats for each workflow.

    Runs and WorkOrders counting are grouped by state.
    """
    defstruct last_workorder: %{state: nil, updated_at: nil},
              last_failed_workorder: %{state: nil, updated_at: nil},
              failed_workorders_count: 0,
              grouped_runs_count: %{},
              grouped_workorders_count: %{},
              step_count: 0,
              step_success_rate: 0.0,
              workorders_count: 0,
              workflow: %Workflow{}
  end

  defmodule ProjectMetrics do
    @moduledoc """
    Aggregated metrics for a project.
    """
    defstruct work_order_metrics: %{
                total: 0,
                pending: 0,
                failed: 0,
                failed_percentage: 0.0
              },
              run_metrics: %{
                total: 0,
                pending: 0,
                success: 0,
                success_rate: 0.0
              }
  end

  def get_workflow_stats(%Workflow{} = workflow) do
    %{failed: failed_wo_count} =
      grouped_workorders_count = count_workorders(workflow)

    workorders_count =
      grouped_workorders_count
      |> Enum.map(fn {_key, count} -> count end)
      |> Enum.sum()

    grouped_runs_count = count_runs(workflow)

    {step_count, step_success_rate} =
      workflow |> count_steps() |> step_stats()

    last_workorder = get_last_workorder(workflow)

    %WorkflowStats{
      workflow: workflow,
      last_workorder: last_workorder,
      last_failed_workorder: get_last_failed_workorder(workflow, last_workorder),
      failed_workorders_count: failed_wo_count,
      grouped_runs_count: grouped_runs_count,
      grouped_workorders_count: grouped_workorders_count,
      step_count: step_count,
      step_success_rate: round(step_success_rate * 100) / 100,
      workorders_count: workorders_count
    }
  end

  @doc """
  Sorts a list of workflow statistics based on the specified field and direction.

  ## Parameters
    * `workflow_stats` - A list of WorkflowStats structs to be sorted
    * `sort_field` - Atom representing the field to sort by, options include:
      * `:last_workorder_updated_at` - Sort by timestamp of the latest work order
      * `:workorders_count` - Sort by total count of work orders
      * `:failed_workorders_count` - Sort by count of failed work orders
    * `sort_direction` - Atom representing sort direction, either :asc or :desc

  ## Returns
    Sorted list of WorkflowStats structs

  ## Examples

      iex> sort_workflow_stats(workflow_stats, :workorders_count, :desc)
      [%WorkflowStats{workorders_count: 100, ...}, %WorkflowStats{workorders_count: 50, ...}]

      iex> sort_workflow_stats(workflow_stats, :last_workorder_updated_at, :asc)
      [%WorkflowStats{last_workorder: %{updated_at: ~U[2023-01-01 00:00:00Z]}, ...}, ...]
  """
  def sort_workflow_stats(workflow_stats, sort_field, sort_direction)
      when is_atom(sort_field) and is_atom(sort_direction) do
    sorter = get_sorter(sort_field)
    Enum.sort_by(workflow_stats, sorter, sort_direction)
  end

  defp get_sorter(:last_workorder_updated_at) do
    fn stats ->
      stats.last_workorder.updated_at || ~U[1970-01-01 00:00:00Z]
    end
  end

  defp get_sorter(field) do
    fn stats -> Map.get(stats, field) end
  end

  def aggregate_project_metrics(workflows_stats) do
    %ProjectMetrics{
      work_order_metrics:
        aggregate_metrics(workflows_stats, :grouped_workorders_count),
      run_metrics: aggregate_metrics(workflows_stats, :grouped_runs_count)
    }
  end

  defp step_stats(%{
         success: success_count,
         failed: failed_count,
         pending: pending_count
       }) do
    step_count = success_count + failed_count + pending_count

    if success_count == 0 do
      {0, 0.0}
    else
      success_rate = success_count * 100 / (success_count + failed_count)
      {step_count, success_rate}
    end
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
         excluded_states \\ []
       ) do
    from(wo in WorkOrder,
      where: wo.workflow_id == ^workflow_id,
      where: wo.state not in ^excluded_states,
      order_by: [desc: wo.inserted_at],
      select: %{state: wo.state, updated_at: wo.updated_at}
    )
    |> filter_days_ago(30)
    |> limit(1)
    |> Repo.one() ||
      %{state: nil, updated_at: nil}
  end

  defp count_workorders(%Workflow{id: workflow_id}) do
    days_ago = DateTime.utc_now() |> DateTime.add(-30, :day)

    from(wo in WorkOrder,
      where: wo.workflow_id == ^workflow_id and wo.inserted_at > ^days_ago,
      group_by: wo.state,
      select: {wo.state, count(wo.id)}
    )
    |> Repo.all()
    |> Enum.reduce(%{success: 0, failed: 0, pending: 0}, fn
      {:success, cnt}, acc ->
        %{acc | success: cnt}

      {state, cnt}, acc when state in [:pending, :running] ->
        Map.update!(acc, :pending, &(&1 + cnt))

      {_other, cnt}, acc ->
        Map.update!(acc, :failed, &(&1 + cnt))
    end)
  end

  defp count_runs(%Workflow{id: workflow_id}) do
    days_ago = DateTime.utc_now() |> DateTime.add(-30, :day)

    from(r in Run,
      join: wo in assoc(r, :work_order),
      where: wo.workflow_id == ^workflow_id and r.inserted_at > ^days_ago,
      group_by: r.state,
      select: {r.state, count(r.id)}
    )
    |> Repo.all()
    |> Enum.reduce(%{success: 0, failed: 0, pending: 0}, fn
      {:success, cnt}, acc ->
        %{acc | success: cnt}

      {state, cnt}, acc when state in [:available, :claimed, :started] ->
        Map.update!(acc, :pending, &(&1 + cnt))

      {_other, cnt}, acc ->
        Map.update!(acc, :failed, &(&1 + cnt))
    end)
  end

  defp count_steps(%Workflow{id: workflow_id}) do
    days_ago = DateTime.utc_now() |> DateTime.add(-30, :day)

    from(s in Step,
      join: j in assoc(s, :job),
      where: j.workflow_id == ^workflow_id and s.inserted_at > ^days_ago,
      group_by: s.exit_reason,
      select: {s.exit_reason, count(s.id)}
    )
    |> Repo.all()
    |> Enum.reduce(%{success: 0, failed: 0, pending: 0}, fn
      {"success", cnt}, acc -> %{acc | success: cnt}
      {nil, cnt}, acc -> %{acc | pending: cnt}
      {_other, cnt}, acc -> Map.update!(acc, :failed, &(&1 + cnt))
    end)
  end

  defp aggregate_metrics(workflows, grouped_entity_count) do
    Enum.reduce(
      workflows,
      %{success: 0, failed: 0, pending: 0, total: 0},
      fn stats,
         %{
           success: acc_success,
           failed: acc_failed,
           pending: acc_pending,
           total: acc_total
         } ->
        %{success: success, failed: failed, pending: pending} =
          Map.get(stats, grouped_entity_count)

        total = success + failed + pending

        %{
          success: acc_success + success,
          failed: acc_failed + failed,
          pending: acc_pending + pending,
          total: acc_total + total
        }
      end
    )
    |> then(fn %{success: success, failed: failed, total: total} = map ->
      completed = success + failed
      failed_percent = if completed > 0, do: failed * 100 / total, else: 0.0
      success_rate = if completed > 0, do: success * 100 / completed, else: 0.0

      Map.merge(map, %{
        success_rate: round(success_rate * 100) / 100,
        failed_percentage: round(failed_percent * 100) / 100
      })
    end)
  end

  def filter_days_ago(query, days) do
    days_ago = DateTime.utc_now() |> DateTime.add(-days * 24 * 60 * 60)

    query
    |> where([r], r.inserted_at > ^days_ago)
  end
end
