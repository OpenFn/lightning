defmodule Lightning.KafkaTriggers.MessageCandidateSetWorkerTest do
  use Lightning.DataCase, async: false

  alias Lightning.KafkaTriggers.MessageCandidateSetServer
  alias Lightning.KafkaTriggers.MessageCandidateSetWorker
  alias Lightning.KafkaTriggers.TriggerKafkaMessage
  alias Lightning.WorkOrder

  describe ".init/1" do
    test "successfully starts the worker with empty state" do
      {:ok, []} = MessageCandidateSetWorker.init([])
    end

    test "queues a message to trigger a request to request a candidate set" do
      MessageCandidateSetWorker.init([])

      assert_receive :request_candidate_set, 1500
    end
  end

  describe ".handle_info :requst_candidate_set - no candidate set available" do
    setup do
      {:ok, _server_pid} = start_supervised(MessageCandidateSetServer)

      :ok
    end

    test "it enqueues a request to trigger the action after a delay" do
      MessageCandidateSetWorker.handle_info(:request_candidate_set, []) 

      assert_receive :request_candidate_set, 2500
    end
  end

  describe ".handle_info :request_candidate_set - candidate set available" do
    setup do
      message =
        insert(
          :trigger_kafka_message,
          key: "test-key",
          work_order: nil
        )

      {:ok, _server_pid} = start_supervised(MessageCandidateSetServer)

      %{
        message: message,
      }
    end

    test "processes the candidate for the candidate set", %{
      message: message,
    } do
      MessageCandidateSetWorker.handle_info(:request_candidate_set, []) 

      assert %{work_order: %WorkOrder{}} =
               TriggerKafkaMessage
               |> Repo.get(message.id)
               |> Repo.preload(:work_order)
    end

    test "it enqueues a request to trigger the action after a delay" do
      MessageCandidateSetWorker.handle_info(:request_candidate_set, []) 

      assert_receive :request_candidate_set, 1500
    end
  end
end
