defmodule Lightning.KafkaTriggers.TriggerKafkaMessage do

  use Ecto.Schema

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
end
