defmodule Lightning.KafkaTriggers.MessageServerTest do
  use Lightning.DataCase

  alias Lightning.KafkaTriggers.MessageServer

  describe ".start_link/1" do
    test "successfully starts the server" do
      pid = start_supervised!(MessageServer)

      assert GenServer.whereis(MessageServer) == pid
    end

    test "initialises with an empty list" do
      assert pid = start_supervised!(MessageServer)

      assert :sys.get_state(pid) == []
    end
  end

  describe ".next_message/0" do
    setup do
      pid = start_supervised!(MessageServer)

      message_1 = insert(:trigger_kafka_message, topic: "topic-1", key: nil)
      message_2 = insert(:trigger_kafka_message, topic: "topic-2", key: nil)

      %{message_1: message_1, message_2: message_2, pid: pid}
    end

    test "returns nil if there are no messages", %{
      message_1: message_1,
      message_2: message_2
    } do
      message_1 |> Repo.delete!()
      message_2 |> Repo.delete!()

      assert MessageServer.next_message() == nil
    end

    test "returns a message id every time when called", %{
      message_1: message_1,
      message_2: message_2
    } do
      first_id = MessageServer.next_message()
      second_id = MessageServer.next_message()

      expected = [message_1.id, message_2.id] |> Enum.sort()

      assert [first_id, second_id] |> Enum.sort() == expected
    end

    test "refreshes state once all cached messages have been returned", %{
      message_1: message_1,
      message_2: message_2,
      pid: pid
    } do
      _first_id = MessageServer.next_message()
      _second_id = MessageServer.next_message()

      assert :sys.get_state(pid) == []

      message_3 = insert(:trigger_kafka_message, topic: "topic-3", key: nil)

      # Now we get all the messages again, including message_3

      first_id = MessageServer.next_message()
      second_id = MessageServer.next_message()
      third_id = MessageServer.next_message()

      expected = [message_1.id, message_2.id, message_3.id] |> Enum.sort()

      assert [first_id, second_id, third_id] |> Enum.sort() == expected
    end
  end
end
