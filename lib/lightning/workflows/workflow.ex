defmodule Lightning.Workflows.Workflow do
  @moduledoc """
  Ecto model for Workflows.

  A Workflow contains the fields for defining a workflow.

  * `name`
    A plain text identifier
  """
  use Lightning.Schema

  alias Lightning.Projects.Project
  alias Lightning.Workflows.Edge
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Workflow
  alias Lightning.Workflows.WorkflowVersion

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          project: nil | Project.t() | Ecto.Association.NotLoaded.t()
        }

  @derive {Jason.Encoder,
           only: [
             :id,
             :name,
             :project_id,
             :edges,
             :jobs,
             :triggers,
             :inserted_at,
             :updated_at
           ]}
  schema "workflows" do
    field :name, :string
    field :concurrency, :integer, default: nil
    field :enable_job_logs, :boolean, default: true
    field :positions, :map
    field :version_history, {:array, :string}, default: []

    has_many :edges, Edge, on_replace: :delete_if_exists
    has_many :jobs, Job, on_replace: :delete
    has_many :triggers, Trigger, on_replace: :delete_if_exists
    has_many :versions, WorkflowVersion, foreign_key: :workflow_id

    has_many :work_orders, Lightning.WorkOrder
    has_many :runs, through: [:work_orders, :runs]
    belongs_to :project, Project

    has_many :snapshots, Snapshot

    field :lock_version, :integer, default: 0
    field :deleted_at, :utc_datetime

    field :delete, :boolean, virtual: true

    timestamps()
  end

  @doc false
  def changeset(workflow, attrs) do
    workflow
    |> cast(attrs, [
      :name,
      :project_id,
      :concurrency,
      :enable_job_logs,
      :positions
    ])
    |> optimistic_lock(:lock_version)
    |> cast_assoc(:edges, with: &Edge.changeset/2)
    |> cast_assoc(:jobs, with: &Job.changeset/2)
    |> cast_assoc(:triggers, with: &Trigger.changeset/2)
    |> validate()
  end

  def validate(changeset) do
    changeset
    |> assoc_constraint(:project)
    |> validate_number(:concurrency, greater_than_or_equal_to: 1)
    |> validate_required([:name])
    |> validate_name_not_deleted_format()
    |> unique_constraint([:name, :project_id],
      message: "a workflow with this name already exists in this project."
    )
  end

  defp validate_name_not_deleted_format(changeset) do
    validate_change(changeset, :name, fn :name, name ->
      if Regex.match?(~r/_del\d*$/, name) do
        [
          name: "cannot end with _del followed by digits"
        ]
      else
        []
      end
    end)
  end

  def request_deletion_changeset(workflow, attrs) do
    workflow
    |> cast(attrs, [:deleted_at])
  end

  @doc """
  Returns true if the workflow has any triggers that are _going to be_ activated.

  New triggers are enabled by default, but existing triggers are only considered
  activated if their `enabled` field is _changed_ to `true`.
  """
  @spec workflow_activated?(Ecto.Changeset.t()) :: boolean()
  def workflow_activated?(%Ecto.Changeset{data: %Workflow{}} = changeset) do
    changeset
    |> get_assoc(:triggers)
    |> Enum.any?(fn trigger_changeset ->
      if trigger_changeset.data.__meta__.state == :built do
        get_field(trigger_changeset, :enabled) == true
      else
        get_change(trigger_changeset, :enabled) == true
      end
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
