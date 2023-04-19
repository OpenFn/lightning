defmodule Lightning.Workflows.Edge do
  @moduledoc """
  Ecto model for Workflow Edges.

  A Workflow Edge represents a connection between two jobs
  (or a trigger and a job) in a workflow.

  The source of the edge is either a job or a trigger.
  The target of the edge is always a job.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Workflows.Workflow
  alias Lightning.Jobs.Job
  alias Lightning.Jobs.Trigger

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "workflow_edges" do
    belongs_to :workflow, Workflow
    belongs_to :source_job, Job
    belongs_to :source_trigger, Trigger
    belongs_to :target_job, Job

    field :condition, :string

    timestamps()
  end

  # TODO: Add validation for source_job XOR source_trigger
  # TODO: Ensure that source_* and target_job are in the same workflow
  # TODO: Ensure that source_job and target_job are not the same
  def changeset(edge, attrs) do
    edge
    |> cast(attrs, [
      :workflow_id,
      :source_job_id,
      :source_trigger_id,
      :target_job_id
    ])
    |> foreign_key_constraint(:target_job_id)
  end
end
