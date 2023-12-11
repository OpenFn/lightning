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
        group_by: r.exit_reason,
        select: %{
          exit_reason: r.exit_reason,
          count: count(r.id)
        }
      )

    runs = Repo.all(query)

    {completed_runs, pending_running_runs} =
      Enum.reduce(runs, {0, 0}, fn
        %{exit_reason: "pending"} = run, {completed, pending_running} ->
          {completed, pending_running + run.count}

        %{exit_reason: "running"} = run, {completed, pending_running} ->
          {completed, pending_running + run.count}

        run, {completed, pending_running} ->
          {completed + run.count, pending_running}
      end)

    %{completed_runs: completed_runs, pending_running_runs: pending_running_runs}
  end

  def calculate_successful_runs_and_percentage(project_id) do
    total_and_successful_runs_query =
      from(
        r in Run,
        join: j in assoc(r, :job),
        join: wf in assoc(j, :workflow),
        join: p in assoc(wf, :project),
        where: p.id == ^project_id,
        select: %{
          total_runs: count(r.id),
          successful_runs:
            sum(
              fragment(
                "CASE WHEN ? = 'success' THEN 1 ELSE 0 END",
                r.exit_reason
              )
            )
        }
      )

    result = Repo.one(total_and_successful_runs_query)

    success_percentage =
      case result do
        nil ->
          0.0

        %{} ->
          if result.total_runs > 0 do
            raw_percentage = result.successful_runs / result.total_runs * 100.0

            if Float.round(raw_percentage, 2) == 100.0 do
              100
            else
              Float.round(raw_percentage, 2)
            end
          else
            0.0
          end
      end

    %{
      successful_runs: result.successful_runs || 0,
      success_percentage: success_percentage
    }
  end

  def calculate_failed_work_orders_and_percentage(project_id) do
    failed_states = [:failed, :crashed, :cancelled, :killed, :exception, :lost]

    # Query for counting failed work orders
    failed_query =
      from(
        wo in WorkOrder,
        join: wf in assoc(wo, :workflow),
        where: wf.project_id == ^project_id and wo.state in ^failed_states,
        select: count(wo.id)
      )

    failed_result = Repo.one(failed_query)

    # Only query total work orders if there are failed results
    total_result =
      if failed_result > 0 do
        total_query =
          from(
            wo in WorkOrder,
            join: wf in assoc(wo, :workflow),
            where: wf.project_id == ^project_id,
            select: count(wo.id)
          )

        Repo.one(total_query)
      else
        0
      end

    # Calculate the percentage
    failure_percentage =
      if failed_result > 0 and total_result > 0 do
        Float.round(failed_result / total_result * 100, 2)
      else
        0
      end

    %{
      failed_workorders: failed_result || 0,
      failure_percentage: failure_percentage
    }
  end
end
