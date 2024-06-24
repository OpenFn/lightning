defmodule Lightning.Workflows.Triggers.Events do
  defmodule KafkaTriggerUpdated do
    @moduledoc false
    defstruct trigger: nil
  end

  def kafka_trigger_updated(trigger) do
    Lightning.broadcast(
      kafka_trigger_updated_topic(),
      %KafkaTriggerUpdated{trigger: trigger}
    )
  end

  def subscribe_to_kafka_trigger_updated() do
    Lightning.subscribe(kafka_trigger_updated_topic())
  end

  def kafka_trigger_updated_topic, do: "kafka_trigger_updated"
end
