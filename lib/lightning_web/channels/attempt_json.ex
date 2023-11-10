defmodule LightningWeb.AttemptJson do
  alias Lightning.Attempt
  alias Lightning.Workflows.{Trigger, Edge, Job}

  def render(%Attempt{} = attempt) do
    %{
      "id" => attempt.id,
      "triggers" => attempt.workflow.triggers |> Enum.map(&render/1),
      "jobs" => attempt.workflow.jobs |> Enum.map(&render/1),
      "edges" => attempt.workflow.edges |> Enum.map(&render/1),
      "starting_node_id" =>
        attempt.starting_trigger_id || attempt.starting_job_id,
      "dataclip_id" => attempt.dataclip_id
    }
  end

  def render(%Trigger{} = trigger) do
    %{
      "id" => trigger.id
    }
  end

  def render(%Job{} = job) do
    %{
      "id" => job.id,
      "adaptor" => job.adaptor,
      "credential_id" => get_credential_id(job),
      "body" => job.body,
      "name" => job.name
    }
  end

  def render(%Edge{} = edge) do
    %{
      "id" => edge.id,
      "source_trigger_id" => edge.source_trigger_id,
      "source_job_id" => edge.source_job_id,
      "condition" => edge.condition,
      "enabled" => edge.enabled,
      "target_job_id" => edge.target_job_id
    }
  end

  defp get_credential_id(job) do
    job.credential
    |> case do
      nil -> nil
      c -> c.id
    end
  end
end
