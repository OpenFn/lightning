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
    belongs_to :job, Job
    belongs_to :upstream_job, Job

    field :type, Ecto.Enum,
      values: @trigger_types,
      default: :webhook

    timestamps()
  end

  @doc false
  def changeset(trigger, attrs) do
    trigger
    |> cast(attrs, [
      :comment,
      :custom_path,
      :type,
      :upstream_job_id,
      :cron_expression
    ])
    |> validate_required([:type])
    |> assoc_constraint(:job)
    |> validate_by_type()
  end

  defp validate_cron(changeset, _options \\ []) do
    validate_change(changeset, :cron_expression, fn _, cron_expression ->
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
        |> assoc_constraint(:upstream_job)

      :webhook ->
        changeset
        |> put_change(:cron_expression, nil)
        |> put_change(:upstream_job_id, nil)

      :cron ->
        changeset
        |> validate_cron()
        |> put_change(:upstream_job_id, nil)
    end
  end
end
