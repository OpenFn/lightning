defmodule LightningWeb.AttemptJson do
  alias Lightning.Attempt
  alias Lightning.Workflows.{Trigger, Edge}
  alias Lightning.Jobs.Job

  def render(attempt = %Attempt{}) do
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

  def render(trigger = %Trigger{}) do
    %{
      "id" => trigger.id
    }
  end

  def render(job = %Job{}) do
    %{
      "id" => job.id,
      "name" => job.name
    }
  end

  def render(edge = %Edge{}) do
    %{
      "id" => edge.id
    }
  end
end
