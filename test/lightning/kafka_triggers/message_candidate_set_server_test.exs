defmodule Lightning.KafkaTriggers.MessageCandidateSetServerTest do
  use Lightning.DataCase

  alias Lightning.KafkaTriggers.MessageCandidateSetServer

  describe ".start_link/1" do
    test "successfully starts the server as a named process" do
      assert {:ok, pid} = MessageCandidateSetServer.start_link([])

      assert GenServer.whereis(MessageCandidateSetServer) == pid
    end

    test "initialises with an empty list" do
      assert {:ok, pid} = MessageCandidateSetServer.start_link([])

      assert :sys.get_state(pid) == []
    end
  end

  describe ".get_candidate_set/0" do
    setup do
      {:ok, pid} = MessageCandidateSetServer.start_link([])

      trigger = insert(:trigger, type: :kafka)

      message_1 =
        insert(
          :trigger_kafka_message,
          trigger: trigger,
          topic: "topic-1",
          key: "key-1"
        )

      message_2 =
        insert(
          :trigger_kafka_message,
          trigger: trigger,
          topic: "topic-2",
          key: "key-2"
        )

      %{
        message_1: message_1,
        message_2: message_2,
        pid: pid,
        trigger: trigger
      }
    end

    test "returns nil if there are no messages", %{
      message_1: message_1,
      message_2: message_2
    } do
      message_1 |> Repo.delete!()
      message_2 |> Repo.delete!()

      assert MessageCandidateSetServer.next_candidate_set() == nil
    end

    test "returns a candidate set map each time called", %{
      pid: pid,
      trigger: trigger
    } do
      trigger_id = trigger.id

      first_set = MessageCandidateSetServer.next_candidate_set()
      second_set = MessageCandidateSetServer.next_candidate_set()

      sorted_sets =
        [first_set, second_set]
        |> Enum.sort_by(& &1.topic)

      assert :sys.get_state(pid) == []

      assert [
               %{trigger_id: ^trigger_id, topic: "topic-1", key: "key-1"},
               %{trigger_id: ^trigger_id, topic: "topic-2", key: "key-2"}
             ] = sorted_sets
    end

    test "refreshes the state with all messages when state has emptied", %{
      pid: pid,
      trigger: trigger
    } do
      trigger_id = trigger.id

      _first_set = MessageCandidateSetServer.next_candidate_set()
      _second_set = MessageCandidateSetServer.next_candidate_set()

      assert :sys.get_state(pid) == []

      _message_3 =
        insert(
          :trigger_kafka_message,
          trigger: trigger,
          topic: "topic-3",
          key: "key-3"
        )

      # Now, we start over with all 3 messages
      first_set = MessageCandidateSetServer.next_candidate_set()
      second_set = MessageCandidateSetServer.next_candidate_set()
      third_set = MessageCandidateSetServer.next_candidate_set()

      sorted_sets =
        [first_set, second_set, third_set]
        |> Enum.sort_by(& &1.topic)

      assert [
               %{trigger_id: ^trigger_id, topic: "topic-1", key: "key-1"},
               %{trigger_id: ^trigger_id, topic: "topic-2", key: "key-2"},
               %{trigger_id: ^trigger_id, topic: "topic-3", key: "key-3"}
             ] = sorted_sets
    end
  end
end
