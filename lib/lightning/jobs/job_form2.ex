# defmodule Lightning.Jobs.JobFormSchema do
#   use Ecto.Schema
#   import Ecto.Changeset

#   embedded_schema do
#     field :adaptor, :string
#     field :body, :string
#     field :enabled, :boolean, default: false
#     field :name, :string
#   end

#   @required_fields [:name, :body, :enabled, :adaptor]

#   def changeset(trigger, attrs \\ %{}) do
#     trigger
#     |> cast(attrs, @required_fields)
#     |> validate_required(@required_fields)
#     |> validate_length(:name, max: 100)
#     |> validate_format(:name, ~r/^[a-zA-Z0-9_\- ]*$/)
#   end
# end

# defmodule Lightning.Jobs.TriggerFormSchema do
#   use Ecto.Schema
#   import Ecto.Changeset

#   @flow_types [:on_job_success, :on_job_failure]
#   @trigger_types [:webhook, :cron] ++ @flow_types

#   embedded_schema do
#     field :type, Ecto.Enum, values: @trigger_types, default: :webhook

#     field :cron_expression, :string
#     field :upstream_job_id, Ecto.UUID
#   end

#   def changeset(trigger, attrs \\ %{}) do
#     trigger
#     |> cast(attrs, [:type, :upstream_job_id, :cron_expression])
#     |> validate_required([:type])
#   end
# end

defmodule Lightning.Jobs.JobForm2 do
  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Jobs.{Trigger, Job}
  alias Lightning.Workflows.Workflow
  alias Ecto.Multi

  @flow_types [:on_job_success, :on_job_failure]
  @trigger_types [:webhook, :cron] ++ @flow_types

  embedded_schema do
    field :project_id, Ecto.UUID
    field :workflow_id, Ecto.UUID
    field :trigger_id, Ecto.UUID
    field :job_id, Ecto.UUID

    field :trigger_type, Ecto.Enum, values: @trigger_types, default: :webhook
    field :trigger_cron_expression, :string
    field :trigger_upstream_job_id, Ecto.UUID

    field :adaptor, :string
    field :body, :string
    field :enabled, :boolean, default: false
    field :name, :string
  end

  @required_fields [:project_id, :name, :body, :enabled, :adaptor, :trigger_type]
  @optional_fields [
    :workflow_id,
    :trigger_id,
    :job_id,
    :trigger_cron_expression,
    :trigger_upstream_job_id
  ]

  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, max: 100)
    |> validate_format(:name, ~r/^[a-zA-Z0-9_\- ]*$/)
  end

  def to_multi(form, attrs) do
    Multi.new()
    |> Multi.run(:workflow, fn repo, _ ->
      form
      |> get_field(:workflow_id)
      |> case do
        nil -> %Workflow{}
        workflow_id -> repo.get(Workflow, workflow_id)
      end
      |> Workflow.changeset(attrs)
      |> repo.insert_or_update()
    end)
    |> Multi.run(:trigger, fn repo, %{workflow: workflow} ->
      attrs = %{
        "type" => Map.get(attrs, "trigger_type"),
        "cron_expression" => Map.get(attrs, "trigger_cron_expression"),
        "upstream_job_id" => Map.get(attrs, "trigger_upstream_job_id"),
        "workflow_id" => workflow.id
      }

      form
      |> get_field(:trigger_id)
      |> case do
        nil -> %Trigger{}
        trigger_id -> repo.get(Trigger, trigger_id)
      end
      |> Trigger.changeset(attrs)
      |> IO.inspect()
      |> repo.insert_or_update()
    end)
    |> Multi.run(:job, fn repo, %{workflow: workflow, trigger: trigger} ->
      attrs =
        attrs
        |> Map.take(["adaptor", "enabled", "body", "name"])
        |> Map.merge(%{
          "workflow_id" => workflow.id,
          "trigger_id" => trigger.id
        })

      form
      |> get_field(:job_id)
      |> case do
        nil -> %Job{}
        job_id -> repo.get(Job, job_id)
      end
      |> Job.changeset(attrs)
      |> repo.insert_or_update()
    end)
  end
end
