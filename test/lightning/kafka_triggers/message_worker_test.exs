defmodule Lightning.KafkaTriggers.MessageWorkerTest do
  use Lightning.DataCase

  alias Lightning.KafkaTriggers.MessageServer
  alias Lightning.KafkaTriggers.MessageWorker
  alias Lightning.Repo

  setup do
    start_supervised!(MessageServer)

    %{state: [no_set_delay: 200, next_set_delay: 100]}
  end

  describe ".start_link/1" do
    test "successfully starts the worker with provided state", %{state: opts} do
      assert pid = start_supervised!({MessageWorker, opts})

      assert :sys.get_state(pid) == opts
    end
  end

  describe ".init/1" do
    test "successfully starts the worker with requested state", %{
      state: state
    } do
      assert {:ok, ^state} = MessageWorker.init(state)
    end

    test "enqueues a message to trigger a request for a message", %{
      state: state
    } do
      MessageWorker.init(state)

      assert_receive :request_message, 1100
    end
  end

  describe ".handle_info :request_message - no message available" do
    test "enqueues a request to repeat the lookup after a delay" do
      delay = 100

      state = [no_set_delay: delay, next_set_delay: delay * 10]

      MessageWorker.handle_info(:request_message, state)

      assert_receive :request_message, delay + 100
    end

    test "returns the passed in state", %{state: state} do
      response =
        MessageWorker.handle_info(:request_message, state)

      assert response == {:noreply, state}
    end
  end

  describe ".handle_info :request_message - message available" do
    setup do
      message =
        insert(
          :trigger_kafka_message,
          topic: "topic-1",
          key: nil,
          work_order: nil
        )

      %{message: message}
    end

    test "returns the passed in state", %{state: state} do
      response =
        MessageWorker.handle_info(:request_message, state)

      assert response == {:noreply, state}
    end

    test "processes the message", %{
      message: message,
      state: state
    } do
      MessageWorker.handle_info(:request_message, state)

      reloaded_message =
        Lightning.KafkaTriggers.TriggerKafkaMessage
        |> Repo.get!(message.id)
        |> Repo.preload(:work_order)

      %{work_order: work_order} = reloaded_message

      assert work_order != nil
    end

    test "enqueues a request to fetch another message after a delay" do
      delay = 100

      state = [no_set_delay: delay * 10, next_set_delay: delay]

      MessageWorker.handle_info(:request_message, state)

      assert_receive :request_message, delay + 100
    end
  end
end
