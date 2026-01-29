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

  # NOTE: This is a temporary structure, we needed a way to programmatically get both
  # the event names, descriptions and tag values all in one place so we can seed
  # these counters with 0 on app start.
  # There is likely some improvements to be made, either by just pulling the seed
  # logic (the part that exposes the exact ETS keys) into this module itself.
  @metric_definitions [
    {@sandbox_created_event ++ [:count],
     [description: "Count of sandbox projects created."]},
    {@sandbox_merged_event ++ [:count],
     [description: "Count of sandbox projects merged into targets."]},
    {@sandbox_deleted_event ++ [:count],
     [description: "Count of sandbox projects manually deleted."]},
    {@workflow_saved_event ++ [:count],
     [
       tags: %{is_sandbox: [true, false]},
       description: "Count of workflow saves, tagged by project type."
     ]},
    {@provisioner_import_event ++ [:count],
     [
       tags: %{is_sandbox: [true, false]},
       description: "Count of provisioner imports, tagged by project type."
     ]}
  ]

  # Expose for external use
  def metric_definitions, do: @metric_definitions

  @impl true
  def event_metrics(_opts) do
    metrics =
      Enum.map(@metric_definitions, fn {name, opts} ->
        opts = Keyword.update(opts, :tags, [], &Map.keys/1)
        Metrics.counter(name, opts)
      end)

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
