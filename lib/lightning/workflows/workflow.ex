defmodule Lightning.Workflows.Workflow do
  @moduledoc """
  Ecto model for Workflows.

  A Workflow contains the fields for defining a workflow.

  * `name`
    A plain text identifier
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Jobs.{Job, Trigger}
  alias Lightning.Projects.Project

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          project: nil | Project.t() | Ecto.Association.NotLoaded.t()
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "workflows" do
    field :name, :string

    has_many :jobs, Job
    has_many :triggers, Trigger
    has_many :work_orders, Lightning.WorkOrder
    has_many :attempts, through: [:work_orders, :attempts]
    belongs_to :project, Project

    field :deleted_at, :utc_datetime

    timestamps()
  end

  @doc false
  def changeset(workflow, attrs) do
    workflow
    |> cast(attrs, [:name, :project_id])
    |> cast_assoc(:jobs, with: &Job.changeset/2)
    |> cast_assoc(:triggers, with: &Job.changeset/2)
    |> validate()
  end

  def import_changeset(workflow, attrs) do
    change =
      workflow
      |> cast(
        Map.put(attrs, :id, Ecto.UUID.generate()),
        [:name, :project_id, :id]
      )

    workflow_id = change |> get_field(:id)

    change
    |> cast_assoc(:jobs,
      with: {Lightning.Jobs.Job, :changeset, [workflow_id]}
    )
  end

  defp validate(changeset) do
    changeset
    |> assoc_constraint(:project)
    |> unique_constraint([:name, :project_id],
      message: "A workflow with this name does already exist in this project."
    )
  end

  def request_deletion_changeset(workflow, attrs) do
    workflow
    |> cast(attrs, [:deleted_at])
  end
end
