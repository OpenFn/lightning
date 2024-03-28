defmodule Lightning.Workflows.Snapshots do
  alias Lightning.Workflows.Workflow

  defmodule Snapshot do
    use Ecto.Schema

    import Ecto.Changeset

    alias Lightning.Projects.ProjectCredential

    @primary_key {:id, :binary_id, autogenerate: true}
    @foreign_key_type :binary_id
    schema "workflow_snapshots" do
      belongs_to :workflow, Workflow
      field :name, :string

      embeds_many :jobs, Job, primary_key: false do
        field :id, :binary_id, primary_key: true
        field :name, :string
        field :body, :string
        field :adaptor, :string
        belongs_to :project_credential, ProjectCredential
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

      timestamps(type: :utc_datetime_usec)
    end

    def new(workflow) do
      cast(%Snapshot{}, workflow, [:name, :workflow_id])
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
  end

  @associations_to_include [:jobs, :triggers, :edges]

  @spec create(Workflow.t()) ::
          {:ok, Snapshot.t()} | {:error, Ecto.Changeset.t()}
  def create(workflow = %Workflow{}) do
    workflow
    |> Lightning.Repo.preload(:jobs)
    |> Map.from_struct()
    |> Enum.into(%{}, fn {field, value} ->
      case field do
        field when field in @associations_to_include ->
          {field, Enum.map(value, &Map.from_struct/1)}

        :name ->
          {field, value}

        :id ->
          {:workflow_id, value}

        _ ->
          {nil, nil}
      end
    end)
    |> Snapshot.new()
    |> Lightning.Repo.insert()
  end
end
