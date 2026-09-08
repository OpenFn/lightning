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

  @run_active Run.active_states()
  @days_back 30

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

  def get_workflows_stats(workflows) do
    workflow_ids = Enum.map(workflows, & &1.id)
    empty_workorders = %{success: 0, failed: 0, pending: 0, cancelled: 0}
    empty = %{success: 0, failed: 0, pending: 0}

    batched_workorders = batch_count_workorders(workflow_ids)
    batched_runs = batch_count_runs(workflow_ids)
    batched_steps = batch_count_steps(workflow_ids)
    last_workorders = batch_get_last_workorders(workflow_ids)

    last_failed_workorders =
      batch_get_last_workorders(
        workflow_ids,
        WorkOrder.states() -- WorkOrder.failure_states()
      )

    Enum.map(workflows, fn workflow ->
      wf_id = workflow.id

      grouped_workorders_count =
        Map.get(batched_workorders, wf_id, empty_workorders)

      grouped_runs_count = Map.get(batched_runs, wf_id, empty)
      steps_count = Map.get(batched_steps, wf_id, empty)

      workorders_count =
        grouped_workorders_count
        |> Enum.map(fn {_key, count} -> count end)
        |> Enum.sum()

      last_workorder =
        Map.get(last_workorders, wf_id, %{state: nil, updated_at: nil})

      last_failed_workorder =
        if last_workorder.state &&
             WorkOrder.outcome(last_workorder.state) != :failed do
          Map.get(last_failed_workorders, wf_id, %{
            state: nil,
            updated_at: nil
          })
        else
          last_workorder
        end

      {step_count, step_success_rate} = step_stats(steps_count)

      %WorkflowStats{
        workflow: workflow,
        last_workorder: last_workorder,
        last_failed_workorder: last_failed_workorder,
        failed_workorders_count: grouped_workorders_count.failed,
        grouped_runs_count: grouped_runs_count,
        grouped_workorders_count: grouped_workorders_count,
        step_count: step_count,
        step_success_rate: round(step_success_rate * 100) / 100,
        workorders_count: workorders_count
      }
    end)
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

  # `Enum.sort_by/3` with `:asc`/`:desc` does structural term comparison, which
  # on `DateTime` structs orders by struct keys (day before month before year),
  # not chronologically. Returning unix microseconds avoids that pitfall.
  # The leading sentinel (`0` for nil, `1` for present) keeps nil rows
  # cleanly separate from a hypothetical `~U[1970-01-01]` row, so the two
  # can never tie at the comparator.
  defp get_sorter(:last_workorder_updated_at) do
    fn stats ->
      case stats.last_workorder.updated_at do
        nil -> {0, 0}
        dt -> {1, DateTime.to_unix(dt, :microsecond)}
      end
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
          counts = Map.get(stats, grouped_entity_count)

        # Run counts have no :cancelled key; work order counts do.
        cancelled = Map.get(counts, :cancelled, 0)
        total = success + failed + pending + cancelled

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

  def filter_days_ago(query, days, column \\ :inserted_at) do
    days_ago = DateTime.utc_now() |> DateTime.add(-days, :day)

    query
    |> where([r], field(r, ^column) > ^days_ago)
  end

  defp batch_count_workorders(workflow_ids) do
    from(wo in WorkOrder, where: wo.workflow_id in ^workflow_ids)
    |> filter_days_ago(@days_back, :last_activity)
    |> group_by([wo], [wo.workflow_id, wo.state])
    |> select([wo], {wo.workflow_id, wo.state, count(wo.id)})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {wf_id, state, cnt}, acc ->
      current =
        Map.get(acc, wf_id, %{success: 0, failed: 0, pending: 0, cancelled: 0})

      updated = Map.update!(current, WorkOrder.outcome(state), &(&1 + cnt))

      Map.put(acc, wf_id, updated)
    end)
  end

  defp batch_count_runs(workflow_ids) do
    from(r in Run,
      join: wo in assoc(r, :work_order),
      where: wo.workflow_id in ^workflow_ids
    )
    |> filter_days_ago(@days_back)
    |> group_by([r, wo], [wo.workflow_id, r.state])
    |> select([r, wo], {wo.workflow_id, r.state, count(r.id)})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {wf_id, state, cnt}, acc ->
      current = Map.get(acc, wf_id, %{success: 0, failed: 0, pending: 0})

      updated =
        case state do
          :success ->
            %{current | success: cnt}

          s when s in @run_active ->
            Map.update!(current, :pending, &(&1 + cnt))

          _ ->
            Map.update!(current, :failed, &(&1 + cnt))
        end

      Map.put(acc, wf_id, updated)
    end)
  end

  defp batch_count_steps(workflow_ids) do
    from(s in Step,
      join: j in assoc(s, :job),
      where: j.workflow_id in ^workflow_ids
    )
    |> filter_days_ago(@days_back)
    |> group_by([s, j], [j.workflow_id, s.exit_reason])
    |> select([s, j], {j.workflow_id, s.exit_reason, count(s.id)})
    |> Repo.all()
    |> Enum.reduce(%{}, fn {wf_id, exit_reason, cnt}, acc ->
      current = Map.get(acc, wf_id, %{success: 0, failed: 0, pending: 0})

      updated =
        case exit_reason do
          "success" -> %{current | success: cnt}
          nil -> %{current | pending: cnt}
          _ -> Map.update!(current, :failed, &(&1 + cnt))
        end

      Map.put(acc, wf_id, updated)
    end)
  end

  defp batch_get_last_workorders(workflow_ids, excluded_states \\ []) do
    from(wo in WorkOrder,
      where: wo.workflow_id in ^workflow_ids,
      where: wo.state not in ^excluded_states
    )
    |> filter_days_ago(@days_back, :last_activity)
    |> order_by([wo], asc: wo.workflow_id, desc: wo.last_activity)
    |> distinct([wo], [wo.workflow_id])
    |> select([wo], %{
      workflow_id: wo.workflow_id,
      state: wo.state,
      updated_at: wo.updated_at
    })
    |> Repo.all()
    |> Map.new(fn %{workflow_id: wf_id} = wo ->
      {wf_id, Map.delete(wo, :workflow_id)}
    end)
  end
end
