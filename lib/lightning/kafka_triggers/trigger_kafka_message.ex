defmodule Lightning.KafkaTriggers.TriggerKafkaMessage do

  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  schema "trigger_kafka_messages" do
    field :trigger_id,  :binary_id
    field :work_order_id, :binary_id
    field :topic, :string
    field :key, :string
    field :message_timestamp, :integer
    field :metadata, :map
    field :data, :binary

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
  end
end
