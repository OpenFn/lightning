defmodule Lightning.KafkaTriggers.MessageRecoveryTest do
  use Lightning.DataCase

  import Ecto.Query

  alias Lightning.Invocation
  alias Lightning.KafkaTriggers
  alias Lightning.KafkaTriggers.MessageRecovery
  alias Lightning.KafkaTriggers.TriggerKafkaMessageRecord
  alias Lightning.Repo
  alias Lightning.WorkOrder

  describe ".recover_messages" do
    setup %{tmp_dir: tmp_dir} do
      workflow_1 = insert(:workflow) |> with_snapshot()
      workflow_2 = insert(:workflow) |> with_snapshot()

      kafka_configuration = build(:triggers_kafka_configuration)

      trigger_1 =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: kafka_configuration,
          workflow: workflow_1
        )

      trigger_2 =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: kafka_configuration,
          workflow: workflow_2
        )

      trigger_3 =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: kafka_configuration,
          workflow: workflow_2
        )

      message_1 = message_contents_for_serialisation("topic-1", 1, 100)
      message_2 = message_contents_for_serialisation("topic-2", 2, 200)
      message_3 = message_contents_for_serialisation("topic-3", 3, 300)
      message_4 = message_contents_for_serialisation("topic-4", 4, 400)

      write_file(tmp_dir, trigger_1, message_1)
      write_file(tmp_dir, trigger_1, message_2)
      write_file(tmp_dir, trigger_2, message_3)
      write_file(tmp_dir, trigger_3, message_4)

      %{
        message_1: message_1,
        message_2: message_2,
        message_3: message_3,
        message_4: message_4,
        trigger_1: trigger_1,
        trigger_2: trigger_2,
        trigger_3: trigger_3
      }
    end

    @tag :tmp_dir
    test "recovers messages from filesystem - processes them via pipeline", %{
      message_1: message_1,
      message_2: message_2,
      message_3: message_3,
      message_4: message_4,
      tmp_dir: tmp_dir,
      trigger_1: trigger_1,
      trigger_2: trigger_2,
      trigger_3: trigger_3
    } do
      MessageRecovery.recover_messages(tmp_dir)

      assert_recovery(trigger_1, [message_1, message_2])
      assert_recovery(trigger_2, [message_3])
      assert_recovery(trigger_3, [message_4])
    end

    @tag :tmp_dir
    test "updates file extension to indicate that it has been recovered", %{
      message_1: message_1,
      message_2: message_2,
      message_3: message_3,
      message_4: message_4,
      tmp_dir: tmp_dir,
      trigger_1: trigger_1,
      trigger_2: trigger_2,
      trigger_3: trigger_3
    } do
      MessageRecovery.recover_messages(tmp_dir)

      assert_renamed_file(tmp_dir, trigger_1, message_1)
      assert_renamed_file(tmp_dir, trigger_1, message_2)
      assert_renamed_file(tmp_dir, trigger_2, message_3)
      assert_renamed_file(tmp_dir, trigger_3, message_4)
    end

    @tag :tmp_dir
    test "returns :ok if there were no recovery errors", %{
      tmp_dir: tmp_dir
    } do
      assert MessageRecovery.recover_messages(tmp_dir) == :ok
    end

    @tag :tmp_dir
    test "does not update the file extension if message reflects an error", %{
      message_1: message_1,
      message_2: message_2,
      message_3: message_3,
      message_4: message_4,
      tmp_dir: tmp_dir,
      trigger_1: trigger_1,
      trigger_2: trigger_2,
      trigger_3: trigger_3
    } do
      ensure_failure(trigger_1, message_2)

      MessageRecovery.recover_messages(tmp_dir)

      assert_renamed_file(tmp_dir, trigger_1, message_1)
      refute_renamed_file(tmp_dir, trigger_1, message_2)
      assert_renamed_file(tmp_dir, trigger_2, message_3)
      assert_renamed_file(tmp_dir, trigger_3, message_4)
    end

    @tag :tmp_dir
    test "returns an indication of the number of failed recoveries, if any", %{
      message_2: message_2,
      message_4: message_4,
      tmp_dir: tmp_dir,
      trigger_1: trigger_1,
      trigger_3: trigger_3
    } do
      ensure_failure(trigger_1, message_2)
      ensure_failure(trigger_3, message_4)

      assert MessageRecovery.recover_messages(tmp_dir) == {:error, 2}
    end

    @tag :tmp_dir
    test "ignores entries in the base directory that are not directories", %{
      message_1: message_1,
      message_2: message_2,
      message_3: message_3,
      message_4: message_4,
      tmp_dir: tmp_dir,
      trigger_1: trigger_1,
      trigger_2: trigger_2,
      trigger_3: trigger_3
    } do
      File.touch!(Path.join(tmp_dir, ".lightning_storage_check"))

      MessageRecovery.recover_messages(tmp_dir)

      assert_recovery(trigger_1, [message_1, message_2])
      assert_recovery(trigger_2, [message_3])
      assert_recovery(trigger_3, [message_4])
    end

    @tag :tmp_dir
    test "ignores files that do have a `.json` extension", %{
      message_1: message_1,
      message_2: message_2,
      message_3: message_3,
      message_4: message_4,
      tmp_dir: tmp_dir,
      trigger_1: trigger_1,
      trigger_2: trigger_2,
      trigger_3: trigger_3
    } do
      mark_file_as_recovered(tmp_dir, trigger_1, message_2)

      MessageRecovery.recover_messages(tmp_dir)

      assert_recovery(trigger_1, [message_1])
      assert_recovery(trigger_2, [message_3])
      assert_recovery(trigger_3, [message_4])
    end
  end

  defp message_contents_for_serialisation(topic, partition, offset) do
    data =
      %{
        message: "Topic: #{topic}"
      }
      |> Jason.encode!()

    %{
      data: data,
      metadata: %{
        offset: offset,
        partition: partition,
        key: "",
        headers: [
          ["foo_header", "foo_value"],
          ["bar_header", "bar_value"]
        ],
        ts: 1_715_164_718_283,
        topic: topic
      }
    }
  end

  defp write_file(base_dir_path, trigger, message) do
    dump_file_path(base_dir_path, trigger, message)
    |> File.write!(Jason.encode!(message))
  end

  defp dump_file_path(base_dir_path, trigger, message) do
    directory_path =
      base_dir_path
      |> Path.join(trigger.workflow_id)
      |> tap(&File.mkdir/1)

    directory_path
    |> Path.join(
      KafkaTriggers.alternate_storage_file_name(
        trigger.id,
        %Broadway.Message{
          acknowledger: %{},
          data: %{},
          metadata: message.metadata
        }
      )
    )
  end

  defp assert_recovery(trigger, messages) do
    expected_bodies =
      messages
      |> Enum.map(&(&1.data |> Jason.decode!()))
      |> Enum.sort()

    query = from w in WorkOrder, where: w.trigger_id == ^trigger.id

    actual_bodies =
      query
      |> Repo.all()
      |> Repo.preload(dataclip: Invocation.Query.dataclip_with_body())
      |> Enum.map(& &1.dataclip.body["data"])
      |> Enum.sort()

    assert actual_bodies == expected_bodies
  end

  defp assert_renamed_file(base_dir_path, trigger, message) do
    old_file_path = dump_file_path(base_dir_path, trigger, message)
    new_file_path = recovered_file_path(old_file_path)

    assert File.exists?(new_file_path)
    assert !File.exists?(old_file_path)
  end

  defp recovered_file_path(file_path), do: "#{file_path}.recovered"

  defp ensure_failure(trigger, message) do
    %TriggerKafkaMessageRecord{
      trigger_id: trigger.id,
      topic_partition_offset: topic_partition_offset(message)
    }
    |> Repo.insert!()
  end

  defp topic_partition_offset(message) do
    KafkaTriggers.build_topic_partition_offset(%Broadway.Message{
      acknowledger: nil,
      data: nil,
      metadata: message.metadata
    })
  end

  defp refute_renamed_file(base_dir_path, trigger, message) do
    old_file_path = dump_file_path(base_dir_path, trigger, message)
    new_file_path = "#{old_file_path}.recovered"

    assert !File.exists?(new_file_path)
    assert File.exists?(old_file_path)
  end

  defp mark_file_as_recovered(base_dir_path, trigger, message) do
    old_file_path = dump_file_path(base_dir_path, trigger, message)
    new_file_path = recovered_file_path(old_file_path)

    File.rename!(old_file_path, new_file_path)
  end
end
