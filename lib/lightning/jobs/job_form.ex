defmodule Lightning.Jobs.JobFormSchema do
  use Ecto.Schema
  import Ecto.Changeset

  embedded_schema do
    field :adaptor, :string
    field :body, :string
    field :enabled, :boolean, default: false
    field :name, :string
  end

  @required_fields [:name, :body, :enabled, :adaptor]

  def changeset(trigger, attrs \\ %{}) do
    trigger
    |> cast(attrs, @required_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, max: 100)
    |> validate_format(:name, ~r/^[a-zA-Z0-9_\- ]*$/)
  end
end

defmodule Lightning.Jobs.TriggerFormSchema do
  use Ecto.Schema
  import Ecto.Changeset

  @flow_types [:on_job_success, :on_job_failure]
  @trigger_types [:webhook, :cron] ++ @flow_types

  embedded_schema do
    field :type, Ecto.Enum, values: @trigger_types, default: :webhook

    field :cron_expression, :string
    field :upstream_job_id, Ecto.UUID
  end

  def changeset(trigger, attrs \\ %{}) do
    trigger
    |> cast(attrs, [:type, :upstream_job_id, :cron_expression])
    |> validate_required([:type])
  end
end

defmodule Lightning.Jobs.JobForm do
  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Jobs.{Trigger, Job, TriggerFormSchema, JobFormSchema}
  alias Lightning.Workflows.Workflow

  embedded_schema do
    field :project_id, Ecto.UUID

    embeds_one :workflow, Workflow
    embeds_one :trigger, TriggerFormSchema
    embeds_one :job, JobFormSchema
  end

  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, [:project_id])
    |> validate_required([:project_id])
    |> cast_embed(:workflow, with: &Workflow.changeset/2)
    |> cast_embed(:trigger, with: &TriggerFormSchema.changeset/2)
    |> cast_embed(:job, with: &JobFormSchema.changeset/2)
  end

  def to_multi(form, attrs) do
    Ecto.Multi.new()
    |> Ecto.Multi.insert_or_update(:workflow, workflow_changeset(form, attrs))
    |> Ecto.Multi.insert_or_update(:trigger, fn %{workflow: workflow} ->
      trigger_changeset(form, attrs, workflow)
    end)
    |> Ecto.Multi.insert_or_update(:job, fn %{
                                              workflow: workflow,
                                              trigger: trigger
                                            } ->
      job_changeset(form, attrs, workflow, trigger)
    end)
  end

  defp workflow_changeset(form, attrs) do
    workflow_attrs =
      Map.get(attrs, "workflow", %{})
      |> Map.put("project_id", form |> get_field(:project_id))

    Workflow.changeset(form.data.workflow || %Workflow{}, workflow_attrs)
  end

  defp trigger_changeset(form, attrs, workflow) do
    trigger_attrs =
      Map.get(attrs, "trigger", %{})
      |> Map.put("workflow_id", workflow.id)

    Trigger.changeset(form.data.trigger || %Trigger{}, trigger_attrs)
  end

  defp job_changeset(form, attrs, workflow, trigger) do
    job_attrs =
      Map.get(attrs, "job", %{})
      |> Map.put("workflow_id", workflow.id)
      |> Map.put("trigger_id", trigger.id)

    Job.changeset(form.data.job || %Job{}, job_attrs)
  end
end
