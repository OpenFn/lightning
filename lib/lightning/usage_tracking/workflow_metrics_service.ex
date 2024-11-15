defmodule Lightning.UsageTracking.WorkflowMetricsService do
  @moduledoc """
  Builds workflow-related metrics.


  """

  alias Lightning.Repo
  alias Lightning.UsageTracking.RunService
  alias Lightning.UsageTracking.WorkflowMetricsQuery

  def find_eligible_workflows(workflows, date) do
    workflows
    |> Enum.filter(fn workflow -> eligible_workflow?(workflow, date) end)
  end

  def generate_metrics(workflow, cleartext_enabled, date) do
    workflow
    |> metrics_for_runs(date)
    |> add_active_jobs()
    |> Map.delete(:job_ids)
    |> Map.merge(instrument_identity(workflow.id, cleartext_enabled))
  end

  defp metrics_for_runs(workflow, date) do
    chunk_size = Lightning.Config.usage_tracking_run_chunk_size()

    {:ok, updated_metrics} =
      Repo.transaction(fn ->
        workflow
        |> WorkflowMetricsQuery.workflow_runs()
        |> WorkflowMetricsQuery.runs_finished_on(date)
        |> Repo.stream(max_rows: chunk_size)
        |> Stream.chunk_every(chunk_size)
        |> Enum.flat_map(&preload_assocs/1)
        |> Enum.reduce(base_metrics(workflow), metric_updater(date))
      end)

    updated_metrics
  end

  defp preload_assocs(run_chunk), do: Repo.preload(run_chunk, steps: [:job])

  defp base_metrics(%{jobs: jobs}) do
    %{
      no_of_jobs: Enum.count(jobs),
      no_of_runs: 0,
      no_of_steps: 0,
      job_ids: []
    }
  end

  defp metric_updater(date) do
    fn run, acc ->
      %{
        no_of_steps: no_of_steps,
        no_of_runs: no_of_runs,
        job_ids: job_ids
      } = acc

      steps = RunService.finished_steps(run, date)
      active_jobs = RunService.unique_job_ids(steps, date)

      Map.merge(
        acc,
        %{
          no_of_runs: no_of_runs + 1,
          no_of_steps: no_of_steps + Enum.count(steps),
          job_ids: Enum.concat(job_ids, active_jobs)
        }
      )
    end
  end

  defp add_active_jobs(%{job_ids: job_ids} = metrics) do
    metrics
    |> Map.merge(%{
      no_of_active_jobs: job_ids |> Enum.uniq() |> Enum.count()
    })
  end

  defp instrument_identity(identity, false = _cleartext_enabled) do
    %{
      cleartext_uuid: nil,
      hashed_uuid: identity |> build_hash()
    }
  end

  defp instrument_identity(identity, true = _cleartext_enabled) do
    identity
    |> instrument_identity(false)
    |> Map.merge(%{cleartext_uuid: identity})
  end

  defp build_hash(uuid), do: Base.encode16(:crypto.hash(:sha256, uuid))

  defp eligible_workflow?(%{deleted_at: nil, inserted_at: inserted_at}, date) do
    if Date.compare(inserted_at, date) == :gt do
      false
    else
      true
    end
  end

  defp eligible_workflow?(
         %{deleted_at: deleted_at, inserted_at: inserted_at},
         date
       ) do
    if Date.compare(inserted_at, date) == :gt ||
         Date.compare(deleted_at, date) != :gt do
      false
    else
      true
    end
  end
end
