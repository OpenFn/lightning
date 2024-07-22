defmodule Lightning.KafkaTriggers.MessageCandidateSetWorkerTest do
  use Lightning.DataCase, async: false

  alias Lightning.KafkaTriggers.MessageCandidateSetServer
  alias Lightning.KafkaTriggers.MessageCandidateSetWorker
  alias Lightning.KafkaTriggers.TriggerKafkaMessage
  alias Lightning.WorkOrder

  setup do
    %{state: [no_set_delay: 200, next_set_delay: 100]}
  end

  describe ".start_link/1" do
    test "successfully starts the worker with options", %{
      state: opts
    } do
      assert pid = start_supervised!({MessageCandidateSetWorker, opts})

      assert :sys.get_state(pid) == opts
    end
  end

  describe ".init/1" do
    test "successfully starts the worker with requested state", %{
      state: state
    } do
      assert {:ok, ^state} = MessageCandidateSetWorker.init(state)
    end

    test "enqueues a message to trigger a request for a candidate set", %{
      state: state
    } do
      MessageCandidateSetWorker.init(state)

      assert_receive :request_candidate_set, 1100
    end
  end

  describe ".handle_info :request_candidate_set - no candidate set available" do
    setup do
      {:ok, _server_pid} = start_supervised(MessageCandidateSetServer)

      :ok
    end

    test "enqueues a request to repeat the lookup after a delay" do
      delay = 100

      state = [no_set_delay: delay, next_set_delay: delay * 10]

      MessageCandidateSetWorker.handle_info(:request_candidate_set, state)

      assert_receive :request_candidate_set, delay + 100
    end

    test "returns the passed in state", %{state: state} do
      response =
        MessageCandidateSetWorker.handle_info(:request_candidate_set, state)

      assert response == {:noreply, state}
    end
  end

  describe ".handle_info :request_candidate_set - candidate set available" do
    setup context do
      message =
        insert(
          :trigger_kafka_message,
          key: "test-key",
          work_order: nil
        )

      {:ok, _server_pid} = start_supervised(MessageCandidateSetServer)

      context |> Map.merge(%{message: message})
    end

    test "processes the candidate for the candidate set", %{
      message: message,
      state: state
    } do
      MessageCandidateSetWorker.handle_info(:request_candidate_set, state)

      assert %{work_order: %WorkOrder{}} =
               TriggerKafkaMessage
               |> Repo.get(message.id)
               |> Repo.preload(:work_order)
    end

    test "enqueues a request to trigger the action after a delay" do
      delay = 100

      state = [no_set_delay: delay * 10, next_set_delay: delay]

      MessageCandidateSetWorker.handle_info(:request_candidate_set, state)

      assert_receive :request_candidate_set, delay + 100
    end

    test "returns the passed in state", %{state: state} do
      response =
        MessageCandidateSetWorker.handle_info(:request_candidate_set, state)

      assert response == {:noreply, state}
    end
  end
end
