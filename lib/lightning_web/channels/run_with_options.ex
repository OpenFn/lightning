defmodule LightningWeb.RunWithOptions do
  @moduledoc false

  alias Lightning.AdaptorRegistry
  alias Lightning.Run
  alias Lightning.Workflows.Snapshot.Edge
  alias Lightning.Workflows.Snapshot.Job
  alias Lightning.Workflows.Snapshot.Trigger

  @doc """
  Plan.render takes a "run" from `Lightning` and renders a "plan"—a JSON object
  that contains information required by the `Worker` to start execution.

  Note that there is a lot of overlap between the `RunOptions` stored in
  Lightning and the optional arguments that are passed to the worker. (I.e.,
  they are almost the same.) This render function is the single source of truth
  for that mapping: it takes a bunch of Lightning resources and turns them into
  a Worker-executable plan for a run.
  """
  @spec render(Run.t()) :: map()
  def render(%Run{} = run) do
    %{
      "id" => run.id,
      "triggers" => run.snapshot.triggers |> Enum.map(&render/1),
      "jobs" => run.snapshot.jobs |> Enum.map(&render/1),
      "edges" => run.snapshot.edges |> Enum.map(&render/1),
      "starting_node_id" => run.starting_trigger_id || run.starting_job_id,
      "dataclip_id" => run.dataclip_id,
      "options" => options_for_worker(run.options)
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

  @doc """
  Converts `Lightning.Runs.RunOptions` to a map of options that are expected by
  the worker.
  """
  @spec options_for_worker(Lightning.Runs.RunOptions.t()) :: map()
  def options_for_worker(%Lightning.Runs.RunOptions{} = options) do
    %{
      output_dataclips: options.save_dataclips,
      run_timeout_ms: options.run_timeout_ms
    }
  end
end
