defmodule Lightning.Workflows.Workflow do
  @moduledoc """
  Ecto model for Workflows.

  A Workflow contains the fields for defining a workflow.

  * `name`
    A plain text identifier
  """
  use Ecto.Schema

  import Ecto.Changeset

  alias Lightning.Projects.Project
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Trigger

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

    has_many :edges, Edge, on_replace: :delete_if_exists

    has_many :jobs, Job, on_replace: :delete
    has_many :triggers, Trigger

    has_many :work_orders, Lightning.WorkOrder
    has_many :runs, through: [:work_orders, :runs]
    belongs_to :project, Project

    field :deleted_at, :utc_datetime

    field :delete, :boolean, virtual: true

    timestamps()
  end

  @doc false
  def changeset(workflow, attrs) do
    workflow
    |> cast(attrs, [:name, :project_id])
    |> cast_assoc(:edges, with: &Edge.changeset/2)
    |> cast_assoc(:jobs, with: &Job.changeset/2)
    |> cast_assoc(:triggers, with: &Trigger.changeset/2)
    |> validate()
  end

  def validate(changeset) do
    changeset
    |> assoc_constraint(:project)
    |> validate_required([:name])
    |> unique_constraint([:name, :project_id],
      message: "a workflow with this name already exists in this project."
    )
  end

  def request_deletion_changeset(workflow, attrs) do
    workflow
    |> cast(attrs, [:deleted_at])
  end
end
