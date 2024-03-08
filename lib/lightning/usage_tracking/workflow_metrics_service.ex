defmodule Lightning.UsageTracking.WorkflowMetricsService do
  @moduledoc """
  Builds workflow-related metrics.


  """
  alias Lightning.UsageTracking.RunService

  def find_eligible_workflows(workflows, date) do
    workflows
    |> Enum.filter(fn workflow -> eligible_workflow?(workflow, date) end)
  end

  def generate_metrics(workflow, cleartext_enabled, date) do
    runs = RunService.finished_runs(workflow.runs, date)
    steps = RunService.finished_steps(workflow.runs, date)
    active_jobs = RunService.unique_jobs(steps, date)

    %{
      no_of_active_jobs: Enum.count(active_jobs),
      no_of_jobs: Enum.count(workflow.jobs),
      no_of_runs: Enum.count(runs),
      no_of_steps: Enum.count(steps)
    }
    |> Map.merge(instrument_identity(workflow.id, cleartext_enabled))
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
