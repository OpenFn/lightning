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
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow

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

    has_many :snapshots, Snapshot

    field :lock_version, :integer, default: 0
    field :deleted_at, :utc_datetime

    field :delete, :boolean, virtual: true

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(workflow, attrs) do
    workflow
    |> cast(attrs, [:name, :project_id])
    |> optimistic_lock(:lock_version)
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

  @spec workflow_activated?(Ecto.Changeset.t()) :: boolean()
  def workflow_activated?(changeset) do
    case changeset do
      %Ecto.Changeset{data: %Workflow{}} -> get_assoc(changeset, :triggers)
      %Ecto.Changeset{data: %Snapshot{}} -> get_embed(changeset, :triggers)
    end
    |> Enum.any?(fn trigger_changeset ->
      get_field(trigger_changeset, :enabled) == true
    end)
  end

  @doc """
  Forces an update to the workflows `updated_at` timestamp and the
  `lock_version`. This is useful when updating a child record like jobs or
  triggers and a snapshot needs to made; but the Workflow itself didn't change.
  """
  @spec touch(t()) :: Ecto.Changeset.t(t())
  def touch(workflow) do
    workflow
    |> change()
    |> force_change(:updated_at, DateTime.utc_now(:second))
    |> optimistic_lock(:lock_version)
  end
end
