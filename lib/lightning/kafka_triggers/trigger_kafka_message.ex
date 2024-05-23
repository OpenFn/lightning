defmodule Lightning.KafkaTriggers.TriggerKafkaMessage do
  use Ecto.Schema
  import Ecto.Changeset

  alias Lightning.Workflows.Trigger
  alias Lightning.WorkOrder

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id
  schema "trigger_kafka_messages" do
    field :topic, :string
    field :key, :string
    field :message_timestamp, :integer
    field :metadata, :map
    field :data, :binary

    belongs_to :trigger, Trigger
    belongs_to :work_order, WorkOrder

    timestamps()
  end

  def changeset(message, changes) do
    cast_changes = [
      :trigger_id,
      :work_order_id,
      :topic,
      :key,
      :message_timestamp,
      :metadata,
      :data
    ]

    required_changes = [
      :trigger_id,
      :topic,
      :message_timestamp,
      :metadata,
      :data
    ]

    message
    |> cast(changes, cast_changes)
    |> validate_required(required_changes)
    # No test for this - test it
    |> assoc_constraint(:trigger)
  end
end
