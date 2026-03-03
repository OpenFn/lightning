defmodule Lightning.Projects.SandboxPromExPlugin do
  @moduledoc """
  PromEx plugin for sandbox-related telemetry metrics.

  Tracks:
  - Sandbox project creation, merging, and deletion
  - Workflow saves tagged by project type (sandbox vs regular)
  - Provisioner imports tagged by project type
  """

  use PromEx.Plugin
  alias Telemetry.Metrics

  @sandbox_created_event [:lightning, :sandbox, :created]
  @sandbox_merged_event [:lightning, :sandbox, :merged]
  @sandbox_deleted_event [:lightning, :sandbox, :deleted]
  @workflow_saved_event [:lightning, :workflow, :saved]
  @provisioner_import_event [:lightning, :provisioner, :import]

  @doc """
  Seeds all sandbox counter metrics directly in PromEx ETS at value 0.

  This establishes the Prometheus baseline so the first real event is captured,
  without adding phantom events on every server restart.

  Only seeds when PromEx is enabled (via `Lightning.Config.promex_enabled?/0`).
  """
  def seed_event_metrics do
    if Lightning.Config.promex_enabled?() do
      seed_counter(@sandbox_created_event ++ [:count], %{})
      seed_counter(@sandbox_merged_event ++ [:count], %{})
      seed_counter(@sandbox_deleted_event ++ [:count], %{})
      seed_counter(@workflow_saved_event ++ [:count], %{is_sandbox: true})
      seed_counter(@workflow_saved_event ++ [:count], %{is_sandbox: false})
      seed_counter(@provisioner_import_event ++ [:count], %{is_sandbox: true})
      seed_counter(@provisioner_import_event ++ [:count], %{is_sandbox: false})
    end
  end

  defp seed_counter(metric_name, labels) do
    table = Lightning.PromEx.Metrics

    unless :ets.whereis(table) == :undefined do
      :ets.insert_new(table, {{metric_name, labels}, 0})
    end
  end

  @impl true
  def event_metrics(_opts) do
    metrics = [
      Metrics.counter(@sandbox_created_event ++ [:count],
        description: "Count of sandbox projects created."
      ),
      Metrics.counter(@sandbox_merged_event ++ [:count],
        description: "Count of sandbox projects merged into targets."
      ),
      Metrics.counter(@sandbox_deleted_event ++ [:count],
        description: "Count of sandbox projects manually deleted."
      ),
      Metrics.counter(@workflow_saved_event ++ [:count],
        tags: [:is_sandbox],
        description: "Count of workflow saves, tagged by project type."
      ),
      Metrics.counter(@provisioner_import_event ++ [:count],
        tags: [:is_sandbox],
        description: "Count of provisioner imports, tagged by project type."
      )
    ]

    [Event.build(:lightning_sandbox_event_metrics, metrics)]
  end

  @doc "Fires a telemetry event when a sandbox project is created."
  def fire_sandbox_created_event do
    :telemetry.execute(@sandbox_created_event, %{})
  end

  @doc "Fires a telemetry event when a sandbox project is merged into its target."
  def fire_sandbox_merged_event do
    :telemetry.execute(@sandbox_merged_event, %{})
  end

  @doc "Fires a telemetry event when a sandbox project is manually deleted."
  def fire_sandbox_deleted_event do
    :telemetry.execute(@sandbox_deleted_event, %{})
  end

  @doc "Fires a telemetry event when a workflow is saved."
  def fire_workflow_saved_event(is_sandbox) do
    :telemetry.execute(@workflow_saved_event, %{}, %{
      is_sandbox: is_sandbox
    })
  end

  @doc "Fires a telemetry event when a provisioner import occurs."
  def fire_provisioner_import_event(is_sandbox) do
    :telemetry.execute(@provisioner_import_event, %{}, %{
      is_sandbox: is_sandbox
    })
  end
end
