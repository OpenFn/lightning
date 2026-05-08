defmodule Lightning.Workflows.YamlFormat do
  @moduledoc """
  Single boundary between Lightning's runtime structs and YAML files.

  Outbound (export) emits the v2 (CLI-aligned portability) format. Inbound
  parsing currently lives in the browser (see `assets/js/yaml/`); a server-
  side parser will land alongside future YAML upload entrypoints.
  """

  alias Lightning.Projects.Project
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Workflow
  alias Lightning.Workflows.YamlFormat.V2

  @spec serialize_workflow(Workflow.t()) :: {:ok, binary()} | {:error, term()}
  def serialize_workflow(workflow), do: V2.serialize_workflow(workflow)

  @spec serialize_project(Project.t(), [Snapshot.t()] | nil) ::
          {:ok, binary()} | {:error, term()}
  def serialize_project(project, snapshots \\ nil),
    do: V2.serialize_project(project, snapshots)
end
