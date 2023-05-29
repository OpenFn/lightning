defmodule Lightning.Jobs.Trigger do
  @moduledoc """
  Ecto model for Triggers.

  Triggers represent the criteria in which a Job might be invoked.

  ## Types

  ### Webhook (default)

  A webhook trigger allows a Job to invoked (via `Lightning.Invocation`) when it's
  endpoint is called.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Jobs.Job
  alias Lightning.Workflows.Workflow

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil
        }

  @flow_types [:on_job_success, :on_job_failure]
  @trigger_types [:webhook, :cron] ++ @flow_types

  @type trigger_type :: :webhook | :cron | :on_job_success | :on_job_failure

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "triggers" do
    field :comment, :string
    field :custom_path, :string
    field :cron_expression, :string
    has_many :jobs, Job
    belongs_to :workflow, Workflow
    belongs_to :upstream_job, Job

    field :type, Ecto.Enum, values: @trigger_types, default: :webhook

    field :delete, :boolean, virtual: true

    timestamps()
  end

  @doc false
  def changeset(trigger, attrs) do
    changeset =
      trigger
      |> cast(attrs, [
        :id,
        :comment,
        :custom_path,
        :type,
        :workflow_id,
        :upstream_job_id,
        :cron_expression
      ])

    changeset
    |> cast_assoc(:jobs,
      with: {Job, :changeset, [changeset |> get_field(:workflow_id)]}
    )
    |> validate()
  end

  @doc """
  DEPRECATED: Triggers are now created via the workflow, this function is only
  used when creating a Trigger via a Job.
  """
  def changeset(job, attrs, workflow_id) do
    changeset(job, attrs)
    |> put_change(:workflow_id, workflow_id)
    |> validate_required(:workflow_id)
  end

  def validate(changeset) do
    changeset
    |> validate_required([:type])
    |> assoc_constraint(:workflow)
    |> validate_by_type()
  end

  defp validate_cron(changeset, _options \\ []) do
    changeset
    |> validate_change(:cron_expression, fn _, cron_expression ->
      Crontab.CronExpression.Parser.parse(cron_expression)
      |> case do
        {:error, error_message} ->
          [{:cron_expression, error_message}]

        {:ok, _exp} ->
          []
      end
    end)
  end

  # Append validations based on the type of the Trigger.
  # - `:on_job_success` must have an associated upstream Job model.
  # - `:webhook` should _not_ have an upstream Job.
  defp validate_by_type(changeset) do
    changeset
    |> fetch_field!(:type)
    |> case do
      type when type in @flow_types ->
        changeset
        |> put_change(:cron_expression, nil)
        |> validate_required(:upstream_job_id)
        |> assoc_constraint(:upstream_job)

      :webhook ->
        changeset
        |> put_change(:cron_expression, nil)
        |> put_change(:upstream_job_id, nil)

      :cron ->
        changeset
        |> put_default(:cron_expression, "0 0 * * *")
        |> validate_cron()
        |> put_change(:upstream_job_id, nil)

      nil ->
        changeset
    end
  end

  defp put_default(changeset, field, value) do
    changeset
    |> get_field(field)
    |> case do
      nil -> changeset |> put_change(field, value)
      _ -> changeset
    end
  end
end
