defmodule Lightning.Workflows.Snapshot do
  @moduledoc """
  Ecto model for Workflow Snapshots.

  Snapshots are a way to store the state of a workflow at a given point in time.
  """
  use Ecto.Schema

  import Ecto.Changeset
  import Ecto.Query

  alias Ecto.Multi

  alias Lightning.Projects.ProjectCredential
  alias Lightning.Repo
  alias Lightning.Workflows.Workflow

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil,
          name: String.t() | nil,
          workflow: nil | Workflow.t() | Ecto.Association.NotLoaded.t(),
          jobs: [%Lightning.Workflows.Snapshot.Job{}],
          triggers: [%Lightning.Workflows.Snapshot.Trigger{}],
          edges: [%Lightning.Workflows.Snapshot.Edge{}]
        }

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "workflow_snapshots" do
    belongs_to :workflow, Workflow
    field :name, :string
    field :lock_version, :integer

    embeds_many :jobs, Job, primary_key: false do
      field :id, :binary_id, primary_key: true
      field :name, :string
      field :body, :string
      field :adaptor, :string
      belongs_to :project_credential, ProjectCredential, define_field: false
      field :project_credential_id, :binary_id
      has_one :credential, through: [:project_credential, :credential]

      field :inserted_at, :utc_datetime_usec
      field :updated_at, :utc_datetime_usec
    end

    embeds_many :triggers, Trigger, primary_key: false do
      field :id, :binary_id, primary_key: true
      field :comment, :string
      field :custom_path, :string
      field :cron_expression, :string
      field :enabled, :boolean
      field :type, Ecto.Enum, values: [:webhook, :cron]

      field :inserted_at, :utc_datetime
      field :updated_at, :utc_datetime
    end

    embeds_many :edges, Edge, primary_key: false do
      field :id, :binary_id, primary_key: true
      field :source_job_id, :binary_id
      field :source_trigger_id, :binary_id
      field :target_job_id, :binary_id

      field :condition_type, Ecto.Enum,
        values: [:on_job_success, :on_job_failure, :always, :js_expression]

      field :condition_expression, :string
      field :condition_label, :string
      field :enabled, :boolean

      field :inserted_at, :utc_datetime
      field :updated_at, :utc_datetime
    end

    timestamps(type: :utc_datetime_usec, updated_at: false)
  end

  def new(workflow) do
    cast(%__MODULE__{}, workflow, [:name, :lock_version, :workflow_id])
    |> validate_required([:name, :lock_version, :workflow_id])
    |> unique_constraint([:workflow_id, :lock_version],
      error_key: :lock_version,
      message: "exists for this workflow"
    )
    |> cast_embed(:jobs, with: &job_changeset/2)
    |> cast_embed(:triggers, with: &trigger_changeset/2)
    |> cast_embed(:edges, with: &edge_changeset/2)
  end

  @job_fields Lightning.Workflows.Job.__schema__(:fields) -- [:workflow_id]
  @trigger_fields Lightning.Workflows.Trigger.__schema__(:fields) --
                    [:workflow_id]
  @edge_fields Lightning.Workflows.Edge.__schema__(:fields) -- [:workflow_id]

  defp job_changeset(schema, params) do
    schema
    |> cast(params, @job_fields)
    |> validate_required([:id, :inserted_at, :updated_at])
  end

  defp trigger_changeset(schema, params) do
    schema
    |> cast(params, @trigger_fields)
    |> validate_required([:id, :inserted_at, :updated_at])
  end

  defp edge_changeset(schema, params) do
    schema
    |> cast(params, @edge_fields)
    |> validate_required([:id, :inserted_at, :updated_at])
  end

  @associations_to_include [:jobs, :triggers, :edges]

  @spec build(Workflow.t()) :: Ecto.Changeset.t()
  def build(%Workflow{} = workflow) do
    workflow
    |> Repo.preload([:jobs, :edges, :triggers])
    |> Map.from_struct()
    |> Enum.into(%{}, fn {field, value} ->
      case field do
        field when field in @associations_to_include ->
          {field, Enum.map(value, &Map.from_struct/1)}

        field when field in [:name, :lock_version] ->
          {field, value}

        :id ->
          {:workflow_id, value}

        _not_matching ->
          {nil, nil}
      end
    end)
    |> new()
  end

  @spec create(Workflow.t()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def create(%Workflow{} = workflow) do
    build(workflow)
    |> Repo.insert()
  end

  @spec get_all_for(Workflow.t()) :: [t()]
  def get_all_for(%Workflow{} = workflow) do
    from(s in __MODULE__,
      where: s.workflow_id == ^workflow.id,
      order_by: [desc: s.inserted_at]
    )
    |> Repo.all()
  end

  @doc """
  Get the latest snapshot for a workflow, based on the lock_version.

  It returns the latest snapshot regardless of the lock_version of the
  workflow passed in. This is intentional to ensure that
  `get_or_create_latest_for/1` doesn't attempt to create a new snapshot if the
  workflow has been updated elsewhere.
  """
  @spec get_current_for(Workflow.t()) :: t() | nil
  def get_current_for(%Workflow{} = workflow) do
    get_current_query(workflow)
    |> Repo.one()
  end

  defp get_current_query(workflow) do
    from(s in __MODULE__,
      join: w in assoc(s, :workflow),
      where:
        s.workflow_id == ^workflow.id and
          s.lock_version == w.lock_version
    )
  end

  def get_by_version(workflow_id, version) do
    from(s in __MODULE__,
      join: w in assoc(s, :workflow),
      where: s.workflow_id == ^workflow_id and s.lock_version == ^version
    )
    |> Repo.one()
  end

  @doc """
  Get the latest snapshot for a workflow, or create one if it doesn't exist.
  """
  @spec get_or_create_latest_for(Workflow.t()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_latest_for(workflow) do
    Multi.new()
    |> get_or_create_latest_for(workflow)
    |> Repo.transaction()
    |> case do
      {:ok, %{snapshot: snapshot}} -> {:ok, snapshot}
      {:error, _name, error, _multi} -> {:error, error}
    end
  end

  @spec get_or_create_latest_for(Multi.t(), Workflow.t()) :: Multi.t()
  def get_or_create_latest_for(multi, workflow) do
    multi
    |> Multi.one(:__existing, get_current_query(workflow))
    |> Multi.merge(fn %{__existing: snapshot} ->
      return_or_create(snapshot, workflow)
    end)
  end

  defp return_or_create(snapshot, workflow) do
    if snapshot do
      Multi.new() |> Multi.put(:snapshot, snapshot)
    else
      Multi.new()
      |> Multi.one(
        :__workflow,
        from(w in Workflow,
          where: w.id == ^workflow.id,
          preload: [:jobs, :triggers, :edges],
          lock: "FOR UPDATE"
        )
      )
      |> Multi.merge(fn %{__workflow: workflow} ->
        if workflow do
          Multi.new() |> Multi.insert(:snapshot, build(workflow))
        else
          Multi.new() |> Multi.error(:workflow, :no_workflow)
        end
      end)
    end
  end
end
