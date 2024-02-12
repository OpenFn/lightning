defmodule LightningWeb.RunWithOptions do
  @moduledoc false

  alias Lightning.AdaptorRegistry
  alias Lightning.Run
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Trigger
  alias LightningWeb.RunOptions

  @spec render(Run.t(), RunOptions.t()) :: map()
  def render(%Run{} = run, options) do
    run |> render() |> Map.put("options", options)
  end

  def render(%Run{} = run) do
    %{
      "id" => run.id,
      "triggers" => run.workflow.triggers |> Enum.map(&render/1),
      "jobs" => run.workflow.jobs |> Enum.map(&render/1),
      "edges" => run.workflow.edges |> Enum.map(&render/1),
      "starting_node_id" => run.starting_trigger_id || run.starting_job_id,
      "dataclip_id" => run.dataclip_id
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
      "adaptor" => AdaptorRegistry.resolve_adaptor(job.adaptor),
      "credential_id" => get_credential_id(job),
      "body" => job.body,
      "name" => job.name
    }
  end

  def render(
        %Edge{
          condition_type: condition_type,
          condition_expression: condition_expression
        } =
          edge
      ) do
    condition =
      if condition_type == :js_expression do
        condition_expression
      else
        condition_type
      end

    %{
      "id" => edge.id,
      "source_trigger_id" => edge.source_trigger_id,
      "source_job_id" => edge.source_job_id,
      "condition" => condition,
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
