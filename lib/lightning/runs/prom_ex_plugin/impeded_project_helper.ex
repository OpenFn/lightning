defmodule Lightning.Runs.PromExPlugin.ImpededProjectHelper do
  @moduledoc """
  Code to support the generation of the impeded project metric.

  The methods in this module will find workflows that have available runs that
  are older than a given threshold. These workflows can then be checked
  to see if they could benefit from increased worker capacity based on comparing
  inprogress runss against the concurrency limits of the project and workflow.
  """
  import Ecto.Query

  alias Lightning.Repo

  def workflows_with_available_runs_older_than(threshold_time) do
    threshold_time
    |> workflows_with_available_runs_query()
    |> Repo.all()
  end

  defp workflows_with_available_runs_query(threshold_time) do
    workflows_with_available_runs_query =
      from r in Lightning.Run,
        where: r.state == :available and r.inserted_at <= ^threshold_time,
        join: w in assoc(r, :work_order),
        select: w.workflow_id,
        distinct: true

    in_progress_runs_query =
      from r in Lightning.Run,
        where: r.state in [:claimed, :started],
        join: w in assoc(r, :work_order),
        group_by: w.workflow_id,
        select: %{workflow_id: w.workflow_id, count: count(r.id)}

    from wwar in subquery(workflows_with_available_runs_query),
      join: wf in Lightning.Workflows.Workflow,
      on: wf.id == wwar.workflow_id,
      join: p in Lightning.Projects.Project,
      on: p.id == wf.project_id,
      left_join: ipr in subquery(in_progress_runs_query),
      on: wwar.workflow_id == ipr.workflow_id,
      select: %{
        project_id: p.id,
        workflow_id: wf.id,
        project_concurrency: p.concurrency,
        workflow_concurrency: wf.concurrency,
        inprogress_runs_count: coalesce(ipr.count, 0)
      }
  end

  def find_projects_with_unused_concurrency(workflow_stats) do
    workflow_stats
    |> Enum.group_by(& &1.project_id)
    |> Enum.filter(fn {_project_id, workflows} ->
      project_has_unused_concurrency?(workflows)
    end)
    |> Enum.map(fn {project_id, _workflows} -> project_id end)
  end

  def project_has_unused_concurrency?(
        [%{project_concurrency: nil} | _] = workflows
      ) do
    workflows_with_unused_concurrency?(workflows)
  end

  def project_has_unused_concurrency?(
        [%{project_concurrency: project_concurrency} | _] = workflows
      ) do
    total_in_progress_runs(workflows) < project_concurrency &&
      workflows_with_unused_concurrency?(workflows)
  end

  defp total_in_progress_runs(workflows) do
    Enum.sum_by(workflows, & &1.inprogress_runs_count)
  end

  defp workflows_with_unused_concurrency?(workflows) do
    Enum.any?(workflows, fn stats -> workflow_has_unused_concurrency?(stats) end)
  end

  def workflow_has_unused_concurrency?(%{workflow_concurrency: nil}), do: true

  def workflow_has_unused_concurrency?(stats) do
    stats.inprogress_runs_count < stats.workflow_concurrency
  end
end
