defmodule Lightning.Workflows.Triggers.Events do
  defmodule KafkaTriggerUpdated do
    @moduledoc false
    defstruct trigger_id: nil
  end

  def kafka_trigger_updated(trigger_id) do
    Lightning.broadcast(
      kafka_trigger_updated_topic(),
      %KafkaTriggerUpdated{trigger_id: trigger_id}
    )
  end

  def subscribe_to_kafka_trigger_updated() do
    Lightning.subscribe(kafka_trigger_updated_topic())
  end

  def kafka_trigger_updated_topic, do: "kafka_trigger_updated"
end
