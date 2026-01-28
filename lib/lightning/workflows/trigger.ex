defmodule Lightning.Workflows.Trigger do
  @moduledoc """
  Ecto model for Triggers.

  Triggers represent the criteria in which a Job might be invoked.

  ## Types

  ### Webhook (default)

  A webhook trigger allows a Job to invoked (via `Lightning.Invocation`) when it's
  endpoint is called.
  """
  use Lightning.Schema
  import Ecto.Query

  alias Lightning.Workflows.Triggers.KafkaConfiguration
  alias Lightning.Workflows.Workflow

  @type t :: %__MODULE__{
          __meta__: Ecto.Schema.Metadata.t(),
          id: Ecto.UUID.t() | nil
        }
  @type trigger_type :: :webhook | :cron

  @trigger_types [:webhook, :cron, :kafka]
  @webhook_reply_types [:before_start, :after_completion, :custom]

  @derive {Jason.Encoder,
           only: [
             :id,
             :comment,
             :custom_path,
             :cron_expression,
             :type,
             :enabled,
             :webhook_reply
           ]}
  schema "triggers" do
    field :comment, :string
    field :custom_path, :string
    field :cron_expression, :string
    field :enabled, :boolean, default: false

    field :webhook_reply, Ecto.Enum, values: @webhook_reply_types

    belongs_to :workflow, Workflow

    has_many :edges, Lightning.Workflows.Edge, foreign_key: :source_trigger_id

    field :type, Ecto.Enum, values: @trigger_types, default: :webhook

    field :delete, :boolean, virtual: true
    field :has_auth_method, :boolean, virtual: true

    many_to_many :webhook_auth_methods, Lightning.Workflows.WebhookAuthMethod,
      join_through: "trigger_webhook_auth_methods",
      on_replace: :delete

    embeds_one :kafka_configuration, KafkaConfiguration, on_replace: :update

    timestamps()
  end

  def new(attrs) do
    change(%__MODULE__{}, Map.merge(attrs, %{id: Ecto.UUID.generate()}))
    |> change(attrs)
  end

  @doc false
  def changeset(trigger, attrs) do
    trigger
    |> cast_changeset(attrs)
    |> cast_embed(
      :kafka_configuration,
      required: false,
      with: &KafkaConfiguration.changeset/2
    )
    |> validate()
  end

  def cast_changeset(trigger, attrs) do
    cast(trigger, attrs, [
      :id,
      :comment,
      :custom_path,
      :enabled,
      :type,
      :workflow_id,
      :cron_expression,
      :has_auth_method,
      :webhook_reply
    ])
  end

  def validate(changeset) do
    changeset
    |> validate_required([:type])
    |> assoc_constraint(:workflow)
    |> validate_by_type()
    |> unique_constraint(:id, name: "triggers_pkey")
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
        |> put_default(:webhook_reply, :before_start)

      :cron ->
        changeset
        |> put_default(:cron_expression, "0 0 * * *")
        |> validate_cron()
        |> put_change(:kafka_configuration, nil)
        |> put_change(:webhook_reply, nil)

      :kafka ->
        changeset
        |> put_change(:cron_expression, nil)
        |> validate_required([:kafka_configuration])
        |> put_change(:webhook_reply, nil)

      nil ->
        changeset
    end
  end

  defp put_default(changeset, field, value) do
    changeset
    |> get_field(field)
    |> case do
      nil -> changeset |> put_change(field, value)
      _value -> changeset
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
