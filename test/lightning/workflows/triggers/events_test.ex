defmodule Lightning.Workflows.Triggers.EventsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows.Triggers.Events
  alias Lightning.Workflows.Triggers.Events.KafkaTriggerUpdated

  test "can subscribe to events relating to a Kafka trigger being updated" do
    trigger = build(:trigger)

    Events.subscribe_to_kafka_trigger_updated()

    Lightning.broadcast(
      "kafka_trigger_updated",
      %KafkaTriggerUpdated{trigger: trigger}
    )

    assert_receive %KafkaTriggerUpdated{trigger: ^trigger}
  end

  test "can broadcast a kafka trigger updated event" do
    trigger = build(:trigger)

    Events.subscribe_to_kafka_trigger_updated()

    Events.kafka_trigger_updated(trigger)

    assert_receive %KafkaTriggerUpdated{trigger: ^trigger}
  end
end
