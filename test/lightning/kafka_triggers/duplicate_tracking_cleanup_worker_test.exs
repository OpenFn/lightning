defmodule Lightning.KafkaTriggers.DuplicateTrackingCleanupWorkerTest do
  use Lightning.DataCase, async: true

  alias Lightning.KafkaTriggers.DuplicateTrackingCleanupWorker
  alias Lightning.KafkaTriggers.TriggerKafkaMessageRecord
  alias Lightning.Repo

  test "deletes all data that is older than the retention period" do
    retention_period =
      Application.get_env(
        :lightning,
        :kafka_pipelines
      )[:duplicate_tracking_retention_seconds]
    now = DateTime.utc_now()
    retain_offset = -retention_period + 1
    retain_time = now |> DateTime.add(retain_offset)
    discard_offset = -retention_period - 1
    discard_time = now |> DateTime.add(discard_offset)

    record_to_be_retained_1 =
      insert(
        :trigger_kafka_message_record,
        trigger_id: insert(:trigger).id,
        topic_partition_offset: "A",
        inserted_at: retain_time
      )
    record_to_be_retained_2 =
      insert(
        :trigger_kafka_message_record,
        topic_partition_offset: "B",
        trigger_id: insert(:trigger).id,
        inserted_at: retain_time
      )

    record_to_be_discarded_1 =
      insert(
        :trigger_kafka_message_record,
        trigger_id: insert(:trigger).id,
        topic_partition_offset: "C",
        inserted_at: discard_time
      )
    record_to_be_discarded_2 =
      insert(
        :trigger_kafka_message_record,
        trigger_id: insert(:trigger).id,
        topic_partition_offset: "D",
        inserted_at: discard_time
      )
    record_to_be_discarded_3 =
      insert(
        :trigger_kafka_message_record,
        trigger_id: insert(:trigger).id,
        topic_partition_offset: "E",
        inserted_at: discard_time
      )
    record_to_be_discarded_4 =
      insert(
        :trigger_kafka_message_record,
        trigger_id: insert(:trigger).id,
        topic_partition_offset: "F",
        inserted_at: discard_time
      )

    perform_job(DuplicateTrackingCleanupWorker, %{})

    refute find_record(record_to_be_discarded_1)
    refute find_record(record_to_be_discarded_2)
    refute find_record(record_to_be_discarded_3)
    refute find_record(record_to_be_discarded_4)

    assert find_record(record_to_be_retained_1)
    assert find_record(record_to_be_retained_2)
  end

  defp find_record(%{topic_partition_offset: topic_partition_offset}) do
    TriggerKafkaMessageRecord
    |> Repo.get_by(topic_partition_offset: topic_partition_offset)
  end
end
