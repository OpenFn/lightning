defmodule Lightning.KafkaTriggers.DuplicateTrackingCleanupWorkerTest do
  use Lightning.DataCase, async: false

  alias Lightning.KafkaTriggers.DuplicateTrackingCleanupWorker
  alias Lightning.KafkaTriggers.TriggerKafkaMessageRecord
  alias Lightning.Repo

  setup do
    retention_period =
      Application.get_env(
        :lightning,
        :kafka_pipelines
      )[:duplicate_tracking_retention_seconds]
    now = DateTime.utc_now()
    retain_offset = -retention_period + 2
    retain_time = now |> DateTime.add(retain_offset)
    discard_offset = -retention_period - 2
    discard_time = now |> DateTime.add(discard_offset)

    records_to_be_retained = [
      insert(
        :trigger_kafka_message_record,
        trigger_id: insert(:trigger).id,
        topic_partition_offset: "A",
        inserted_at: retain_time
      ),
      insert(
        :trigger_kafka_message_record,
        topic_partition_offset: "B",
        trigger_id: insert(:trigger).id,
        inserted_at: retain_time
      )
    ]
    records_to_be_discarded = [
      insert(
        :trigger_kafka_message_record,
        trigger_id: insert(:trigger).id,
        topic_partition_offset: "C",
        inserted_at: discard_time
      ),
      insert(
        :trigger_kafka_message_record,
        trigger_id: insert(:trigger).id,
        topic_partition_offset: "D",
        inserted_at: discard_time
      ),
      insert(
        :trigger_kafka_message_record,
        trigger_id: insert(:trigger).id,
        topic_partition_offset: "E",
        inserted_at: discard_time
      ),
      insert(
        :trigger_kafka_message_record,
        trigger_id: insert(:trigger).id,
        topic_partition_offset: "F",
        inserted_at: discard_time
      )
    ]

    %{
      records_to_be_discarded: records_to_be_discarded,
      records_to_be_retained: records_to_be_retained,
    }
  end

  test "deletes all data that is older than the retention period", %{
    records_to_be_discarded: to_be_discarded,
    records_to_be_retained: to_be_retained
  } do
    [discard_1, discard_2, discard_3, discard_4] = to_be_discarded
    [retain_1, retain_2] = to_be_retained

    perform_job(DuplicateTrackingCleanupWorker, %{})

    refute find_record(discard_1)
    refute find_record(discard_2)
    refute find_record(discard_3)
    refute find_record(discard_4)

    assert find_record(retain_1)
    assert find_record(retain_2)
  end

  test "returns :ok" do
    assert perform_job(DuplicateTrackingCleanupWorker, %{}) == :ok
  end

  defp find_record(%{topic_partition_offset: topic_partition_offset}) do
    TriggerKafkaMessageRecord
    |> Repo.get_by(topic_partition_offset: topic_partition_offset)
  end
end
