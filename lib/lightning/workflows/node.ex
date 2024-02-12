defmodule Lightning.Workflows.Node do
  @moduledoc """
  Represents a node in a workflow graph.
  """
  use Ecto.Schema

  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "workflow_nodes" do
    belongs_to :workflow, Workflow
    belongs_to :job, Job
    belongs_to :trigger, Trigger
  end
end
