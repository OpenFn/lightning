defmodule Lightning.KafkaTriggers.MessageRecoveryTest do
  use Lightning.DataCase

  alias Lightning.Invocation
  alias Lightning.KafkaTriggers
  alias Lightning.KafkaTriggers.MessageRecovery
  alias Lightning.Repo
  alias Lightning.WorkOrder

  describe ".recover_messages" do
    setup do
      workflow_1 = insert(:workflow)
      workflow_2 = insert(:workflow)

      trigger_1 =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: build(:triggers_kafka_configuration),
          workflow: workflow_1
        )
      trigger_2 =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: build(:triggers_kafka_configuration),
          workflow: workflow_2
        )
      trigger_3 =
        insert(
          :trigger,
          type: :kafka,
          kafka_configuration: build(:triggers_kafka_configuration),
          workflow: workflow_2
        )

      %{
        trigger_1: trigger_1,
        trigger_2: trigger_2,
        trigger_3: trigger_3
      }
    end

    @tag :tmp_dir
    test "recovers messages from filesystem - processes them via pipeline", %{
      tmp_dir: tmp_dir,
      trigger_1: trigger_1,
      trigger_2: trigger_2,
      trigger_3: trigger_3,
    } do
      message_1 = message_contents_for_serialisation("topic-1", 1, 100)
      message_2 = message_contents_for_serialisation("topic-2", 2, 200)
      message_3 = message_contents_for_serialisation("topic-3", 3, 300)
      message_4 = message_contents_for_serialisation("topic-4", 4, 400)

      write_file(tmp_dir, trigger_1, message_1)
      write_file(tmp_dir, trigger_1, message_2)
      write_file(tmp_dir, trigger_2, message_3)
      write_file(tmp_dir, trigger_3, message_4)

      MessageRecovery.recover_messages(tmp_dir)

      assert_recovery(trigger_1, message_1)
      assert_recovery(trigger_1, message_2)
      assert_recovery(trigger_2, message_3)
      assert_recovery(trigger_3, message_4)
    end
  end

  defp message_contents_for_serialisation(topic, partition, offset) do
    data = %{
      message: "Topic: #{topic}"
    } |> Jason.encode!()

    %{
      data: data,
      metadata: %{
        offset: offset,
        partition: partition,
        key: "",
        headers: [],
        ts: 1_715_164_718_283,
        topic: topic
      },
    }
  end

  defp write_file(base_dir_path, trigger, message) do
    directory_path =
      base_dir_path
      |> Path.join(trigger.workflow_id)
      |> tap(&File.mkdir/1)

    file_path =
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
    
    File.write!(file_path, Jason.encode!(message))
  end

  defp assert_recovery(trigger, message) do
    assert %WorkOrder{dataclip: dataclip} =
      WorkOrder
      |> Repo.get_by(trigger_id: trigger.id)
      |> Repo.preload(dataclip: Invocation.Query.dataclip_with_body())

    assert dataclip.body["data"] == message.data |> Jason.decode!()
  end
end
