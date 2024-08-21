defmodule Lightning.Workflows.Triggers.Events do
  @moduledoc """
  Responsible for the publishing of and subscription to trigger-related events.
  """
  defmodule KafkaTriggerUpdated do
    @moduledoc false
    defstruct trigger_id: nil
  end

  defmodule KafkaTriggerPersistenceFailure do
    @moduledoc false
    defstruct trigger_id: nil, timestamp: nil
  end

  def kafka_trigger_persistence_failure(trigger_id, timestamp) do
    Lightning.broadcast(
      kafka_trigger_events_topic(),
      %KafkaTriggerPersistenceFailure{
        trigger_id: trigger_id,
        timestamp: timestamp
      }
    )
  end

  def kafka_trigger_updated(trigger_id) do
    Lightning.broadcast(
      kafka_trigger_events_topic(),
      %KafkaTriggerUpdated{trigger_id: trigger_id}
    )
  end

  def subscribe_to_kafka_trigger_events do
    Lightning.subscribe(kafka_trigger_events_topic())
  end

  defp kafka_trigger_events_topic, do: "kafka_trigger_events"
end
