defmodule Lightning.KafkaTriggers.TriggerKafkaMessageRecord do
  @moduledoc """
  Persists a lightweight represenattion of a message that has been recevied from
  a Kafka cluster, for the purpose of deduplication.
  """
  use Ecto.Schema

  import Ecto.Changeset

  @primary_key false
  schema "trigger_kafka_message_records" do
    field :trigger_id, :binary_id
    field :topic_partition_offset, :string

    timestamps(updated_at: false)
  end

  def changeset(message_record, params) do
    message_record
    |> cast(params, [:trigger_id, :topic_partition_offset])
    |> validate_required([:trigger_id, :topic_partition_offset])
    |> unique_constraint(:trigger_id, name: "trigger_kafka_message_records_pkey")
  end
end
