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

  alias Lightning.Workflows.Workflow

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil
        }

  @trigger_types [:webhook, :cron]

  @type trigger_type :: :webhook | :cron
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "triggers" do
    field :comment, :string
    field :custom_path, :string
    field :cron_expression, :string
    belongs_to :workflow, Workflow

    has_many :edges, Lightning.Workflows.Edge, foreign_key: :source_trigger_id

    field :type, Ecto.Enum, values: @trigger_types, default: :webhook

    field :delete, :boolean, virtual: true

    timestamps()
  end

  def new(attrs) do
    change(%__MODULE__{}, Map.merge(attrs, %{id: Ecto.UUID.generate()}))
    |> change(attrs)
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
        :cron_expression
      ])

    changeset
    |> validate()
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
  defp validate_by_type(changeset) do
    changeset
    |> fetch_field!(:type)
    |> case do
      :webhook ->
        changeset
        |> put_change(:cron_expression, nil)

      :cron ->
        changeset
        |> put_default(:cron_expression, "0 0 * * *")
        |> validate_cron()

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
