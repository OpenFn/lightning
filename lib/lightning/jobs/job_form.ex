defmodule Lightning.Jobs.JobForm do
  @moduledoc """
  Schemaless changeset for wrapping the creation of a Workflow, Job and a Trigger
  in one place.

  This is used to faciliate the UI components when making a new Job
  where the form displays the Trigger in the same form.

  However if a Job is new (and doesn't have a Workflow), the associated
  Trigger will not have the requisite `workflow_id`.
  """
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
    field :project_credential_id, Ecto.UUID
    field :trigger_id, Ecto.UUID

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
    :trigger_cron_expression,
    :trigger_upstream_job_id,
    :project_credential_id
  ]

  def changeset(struct, params \\ %{}) do
    struct
    |> cast(params, @required_fields ++ @optional_fields)
    |> validate_required(@required_fields)
    |> validate_length(:name, max: 100)
    |> validate_format(:name, ~r/^[a-zA-Z0-9_\- ]*$/)
  end

  def put_body(struct, body) do
    struct |> put_change(:body, body)
  end

  def from_job(job) do
    job = Lightning.Repo.preload(job, [:workflow, :trigger])

    trigger_attrs =
      Map.take(job.trigger || %{}, [
        :id,
        :type,
        :upstream_job_id,
        :cron_expression
      ])
      |> Enum.into(%{}, fn {k, v} ->
        {"trigger_#{k}" |> String.to_existing_atom(), v}
      end)

    project_id = job.workflow.project_id

    struct(
      __MODULE__,
      Map.from_struct(job)
      |> Map.merge(%{project_id: project_id})
      |> Map.merge(trigger_attrs)
    )
  end

  def to_multi(form, attrs) do
    # TODO: Might not actually need attrs

    Multi.new()
    |> Multi.run(:workflow, fn repo, _ ->
      form
      |> get_field(:workflow_id)
      |> case do
        nil -> %Workflow{}
        workflow_id -> repo.get(Workflow, workflow_id)
      end
      |> Workflow.changeset(%{"project_id" => form |> get_field(:project_id)})
      |> repo.insert_or_update()
    end)
    |> Multi.run(:trigger, fn repo, %{workflow: workflow} ->
      attrs =
        Map.take(attrs, [
          "trigger_type",
          "trigger_cron_expression",
          "trigger_upstream_job_id"
        ])
        |> Enum.into(%{}, fn {k, v} ->
          {k |> String.replace("trigger_", ""), v}
        end)
        |> Map.put("workflow_id", workflow.id)

      form
      |> get_field(:trigger_id)
      |> case do
        nil -> %Trigger{}
        trigger_id -> repo.get(Trigger, trigger_id)
      end
      |> Trigger.changeset(attrs)
      |> repo.insert_or_update()
    end)
    |> Multi.run(:job, fn repo, %{workflow: workflow, trigger: trigger} ->
      attrs =
        Ecto.Changeset.apply_changes(form)
        |> Map.take([:adaptor, :enabled, :body, :name, :project_credential_id])
        |> Map.merge(%{workflow_id: workflow.id, trigger_id: trigger.id})

      form
      |> get_field(:id)
      |> case do
        nil -> %Job{}
        id -> repo.get(Job, id)
      end
      |> Job.changeset(attrs)
      |> repo.insert_or_update()
    end)
  end
end
