defmodule Lightning.Workflows.Node do
  use Ecto.Schema

  alias Lightning.Workflows.Workflow
  alias Lightning.Jobs.Job
  alias Lightning.Jobs.Trigger

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "workflow_nodes" do
    belongs_to :workflow, Workflow
    belongs_to :job, Job
    belongs_to :trigger, Trigger
  end
end
