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
    |> Enum.map(&convert_record_to_map/1)
  end

  defp workflows_with_available_runs_query(threshold_time) do
    from r in Lightning.Run,
      join: w in assoc(r, :workflow),
      join: p in assoc(w, :project),
      left_join: rr in assoc(w, :runs),
      on: rr.state in [:claimed, :started],
      where: r.state == :available,
      where: r.inserted_at <= ^threshold_time,
      select: [
        p.id,
        w.id,
        p.concurrency,
        w.concurrency,
        count(rr.id, :distinct)
      ],
      group_by: [
        p.id,
        w.id,
        p.concurrency,
        w.concurrency
      ]
  end

  defp convert_record_to_map(record) do
    [
      project_id,
      workflow_id,
      project_concurrency,
      workflow_concurrency,
      inprogress_runs_count
    ] = record

    %{
      project_id: project_id,
      workflow_id: workflow_id,
      project_concurrency: project_concurrency,
      workflow_concurrency: workflow_concurrency,
      inprogress_runs_count: inprogress_runs_count
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
