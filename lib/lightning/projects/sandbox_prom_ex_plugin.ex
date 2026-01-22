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

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :lightning_sandbox_event_metrics,
        [
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
      )
    ]
  end

  # Public API for firing events

  @doc "Fires a telemetry event when a sandbox project is created."
  def fire_sandbox_created_event do
    :telemetry.execute(@sandbox_created_event, %{count: 1}, %{})
  end

  @doc "Fires a telemetry event when a sandbox project is merged into its target."
  def fire_sandbox_merged_event do
    :telemetry.execute(@sandbox_merged_event, %{count: 1}, %{})
  end

  @doc "Fires a telemetry event when a sandbox project is manually deleted."
  def fire_sandbox_deleted_event do
    :telemetry.execute(@sandbox_deleted_event, %{count: 1}, %{})
  end

  @doc "Fires a telemetry event when a workflow is saved."
  def fire_workflow_saved_event(is_sandbox) do
    :telemetry.execute(@workflow_saved_event, %{count: 1}, %{
      is_sandbox: is_sandbox
    })
  end

  @doc "Fires a telemetry event when a provisioner import occurs."
  def fire_provisioner_import_event(is_sandbox) do
    :telemetry.execute(@provisioner_import_event, %{count: 1}, %{
      is_sandbox: is_sandbox
    })
  end
end
