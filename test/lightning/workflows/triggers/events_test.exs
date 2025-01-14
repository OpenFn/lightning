defmodule Lightning.Workflows.Triggers.EventsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows.Triggers.Events
  alias Lightning.Workflows.Triggers.Events.KafkaTriggerNotificationSent
  alias Lightning.Workflows.Triggers.Events.KafkaTriggerUpdated

  test "can subscribe to events relating to a Kafka trigger being updated" do
    trigger_id = "a-b-c-1-2-3"

    Events.subscribe_to_kafka_trigger_updated()

    Lightning.broadcast(
      "kafka_trigger_updated",
      %KafkaTriggerUpdated{trigger_id: trigger_id}
    )

    assert_receive %KafkaTriggerUpdated{trigger_id: ^trigger_id}
  end

  test "can broadcast a kafka trigger updated event" do
    trigger_id = Ecto.UUID.generate()

    Events.subscribe_to_kafka_trigger_updated()

    Events.kafka_trigger_updated(trigger_id)

    assert_receive %KafkaTriggerUpdated{trigger_id: ^trigger_id}
  end

  test "can broadcast a kafka trigger notification sent event" do
    trigger_id = "a-b-c-1-2-3"
    sent_at = ~U[2021-01-01 12:00:00Z]

    Events.subscribe_to_kafka_trigger_updated()

    Events.kafka_trigger_notification_sent(trigger_id, sent_at)

    assert_receive(%KafkaTriggerNotificationSent{
      trigger_id: ^trigger_id,
      sent_at: ^sent_at
    })
  end
end
