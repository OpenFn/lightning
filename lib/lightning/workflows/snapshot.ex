defmodule Lightning.Workflows.Snapshot do
  @moduledoc """
  Ecto model for Workflow Snapshots.

  Snapshots are a way to store the state of a workflow at a given point in time.
  """
  use Lightning.Schema

  import Ecto.Query

  alias Ecto.Multi

  alias Lightning.Projects.ProjectCredential
  alias Lightning.Repo
  alias Lightning.Workflows.Audit
  alias Lightning.Workflows.WebhookAuthMethod
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
      field :kafka_configuration, :map
      field :type, Ecto.Enum, values: [:webhook, :cron, :kafka]
      field :has_auth_method, :boolean, virtual: true

      many_to_many :webhook_auth_methods, WebhookAuthMethod,
        join_through: "trigger_webhook_auth_methods",
        on_replace: :delete

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

  def get_all_by_ids(ids) do
    from(s in __MODULE__,
      where: s.id in ^ids
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
      where: s.workflow_id == ^workflow_id and s.lock_version == ^version,
      preload: [triggers: [:webhook_auth_methods]]
    )
    |> Repo.one()
  end

  @doc """
  Get the latest snapshot for a workflow, or create one if it doesn't exist.
  """
  @spec get_or_create_latest_for(Workflow.t(), struct()) ::
          {:ok, t()} | {:error, Ecto.Changeset.t()}
  def get_or_create_latest_for(workflow, actor) do
    Multi.new()
    |> get_or_create_latest_for(workflow, actor)
    |> Repo.transaction()
    |> case do
      {:ok, %{snapshot: snapshot}} -> {:ok, snapshot}
      {:error, _name, error, _multi} -> {:error, error}
    end
  end

  @spec get_or_create_latest_for(
          Multi.t(),
          binary() | :snapshot,
          Workflow.t(),
          struct()
        ) ::
          Multi.t()
  def get_or_create_latest_for(multi, name \\ :snapshot, workflow, actor) do
    unique_op = "_existing#{System.unique_integer()}"

    multi
    |> Multi.one(unique_op, get_current_query(workflow))
    |> Multi.merge(fn %{^unique_op => snapshot} ->
      return_or_create(name, snapshot, workflow, actor)
    end)
  end

  defp return_or_create(name, snapshot, workflow, actor) do
    if snapshot do
      Multi.new() |> Multi.put(name, snapshot)
    else
      unique_op = "_workflow#{System.unique_integer()}"

      audit_snapshot =
        fn %{^name => %{id: snapshot_id}} ->
          Audit.snapshot_created(workflow.id, snapshot_id, actor)
        end

      Multi.new()
      |> Multi.one(
        unique_op,
        from(w in Workflow,
          where: w.id == ^workflow.id,
          preload: [:jobs, :triggers, :edges],
          lock: "FOR UPDATE"
        )
      )
      |> Multi.merge(fn %{^unique_op => workflow} ->
        if workflow do
          Multi.new()
          |> Multi.insert(name, build(workflow))
          |> Multi.insert(String.to_atom("audit_of_#{name}"), audit_snapshot)
        else
          Multi.new() |> Multi.error(:workflow, :no_workflow)
        end
      end)
    end
  end

  @spec include_latest_snapshot(Multi.t(), binary() | :snapshot, Workflow.t()) ::
          Multi.t()
  def include_latest_snapshot(multi, name \\ :snapshot, workflow) do
    get_snapshot  = fn repo, _changes ->
      {:ok, get_current_query(workflow) |> repo.one()}
    end

    multi |> Multi.run(name, get_snapshot)
  end
end
