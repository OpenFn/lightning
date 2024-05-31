defmodule Lightning.Workflows.Trigger do
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
  import Ecto.Query

  alias Lightning.Workflows.Workflow

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil
        }

  @trigger_types [:webhook, :cron, :kafka]

  @type trigger_type :: :webhook | :cron
  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "triggers" do
    field :comment, :string
    field :custom_path, :string
    field :cron_expression, :string
    # field :kafka_configuration, :map
    field :enabled, :boolean, default: true
    belongs_to :workflow, Workflow

    has_many :edges, Lightning.Workflows.Edge, foreign_key: :source_trigger_id

    field :type, Ecto.Enum, values: @trigger_types, default: :webhook

    field :delete, :boolean, virtual: true
    field :has_auth_method, :boolean, virtual: true

    many_to_many :webhook_auth_methods, Lightning.Workflows.WebhookAuthMethod,
      join_through: "trigger_webhook_auth_methods",
      on_replace: :delete

    embeds_one :kafka_configuration, Lightning.Workflows.Trigger.KafkaConfiguration, on_replace: :update

    timestamps(type: :utc_datetime)
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
        :enabled,
        :type,
        :workflow_id,
        :cron_expression,
        :has_auth_method,
      ])
      |> cast_embed(
        :kafka_configuration,
        required: false,
        with: &kafka_configuration_changeset/2
      )

    changeset
    |> validate()
  end

  defp kafka_configuration_changeset(kafka_configuration, attrs) do
    kafka_configuration
    |> cast(attrs, [
      :group_id,
      :hosts,
      :initial_offset_reset_policy,
      :partition_timestamps,
      :password,
      :sasl,
      :ssl,
      :topics,
      :username
    ])
  end

  def validate(changeset) do
    changeset
    |> validate_required([:type])
    |> assoc_constraint(:workflow)
    |> validate_by_type()
  end

  defp validate_cron(changeset, _options \\ []) do
    changeset
    |> validate_change(:cron_expression, fn _field, cron_expression ->
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
        |> put_change(:kafka_configuration, nil)

      :cron ->
        changeset
        |> put_default(:cron_expression, "0 0 * * *")
        |> validate_cron()
        |> put_change(:kafka_configuration, nil)

      :kafka ->
        changeset
        |> put_change(:cron_expression, nil)
        |> validate_required([:kafka_configuration])

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

  def with_auth_methods_query do
    from t in __MODULE__,
      left_join: wam in assoc(t, :webhook_auth_methods),
      preload: [webhook_auth_methods: wam],
      select: %{
        t
        | has_auth_method:
            fragment(
              "CASE WHEN ? IS NULL THEN ? ELSE ? END",
              wam.id,
              false,
              true
            )
      }
  end
end

defmodule Lightning.Workflows.Trigger.KafkaConfiguration do
  use Ecto.Schema

  @derive {Jason.Encoder, only: [
    :group_id,
    :hosts,
    :initial_offset_reset_policy,
    :partition_timestamps,
    :password,
    :sasl,
    :ssl,
    :topics,
    :username
  ]}

  embedded_schema do
    field :group_id, :string
    field :hosts, {:array, {:array, :string}}
    field :initial_offset_reset_policy, :string
    field :partition_timestamps, :map
    field :password, :string
    field :sasl, :string
    field :ssl, :boolean
    field :topics, {:array, :string}
    field :username, :string
  end
end
