defmodule Lightning.Workflows.Triggers.EventsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows.Triggers.Events
  alias Lightning.Workflows.Triggers.Events.KafkaTriggerUpdated
  alias Lightning.Workflows.Triggers.Events.KafkaTriggerPersistenceFailure

  test "can subscribe to events relating to a Kafka trigger being updated" do
    trigger_id = "a-b-c-1-2-3"

    Events.subscribe_to_kafka_trigger_events()

    Lightning.broadcast(
      "kafka_trigger_events",
      %KafkaTriggerUpdated{trigger_id: trigger_id}
    )

    assert_receive %KafkaTriggerUpdated{trigger_id: ^trigger_id}
  end

  test "can broadcast a kafka trigger updated event" do
    trigger_id = Ecto.UUID.generate()

    Events.subscribe_to_kafka_trigger_events()

    Events.kafka_trigger_updated(trigger_id)

    assert_receive %KafkaTriggerUpdated{trigger_id: ^trigger_id}
  end

  test "subscribes to events relating to Kakfa trigger persistence failures" do
    trigger_id = "a-b-c-1-2-3"
    timestamp = 1_723_633_665_366

    Events.subscribe_to_kafka_trigger_events()

    Lightning.broadcast(
      "kafka_trigger_events",
      %KafkaTriggerPersistenceFailure{
        trigger_id: trigger_id,
        timestamp: timestamp
      }
    )

    assert_receive %KafkaTriggerPersistenceFailure{
      trigger_id: ^trigger_id,
      timestamp: ^timestamp
    }
  end

  test "publishes events relating to Kafka trigger persistence failures" do
    trigger_id = "a-b-c-1-2-3"
    timestamp = 1_723_633_665_366

    Events.subscribe_to_kafka_trigger_events()

    Events.kafka_trigger_persistence_failure(trigger_id, timestamp)

    assert_receive %KafkaTriggerPersistenceFailure{
      trigger_id: ^trigger_id,
      timestamp: ^timestamp
    }
  end
end
