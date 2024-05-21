defmodule Lightning.KafkaTriggers.MessageCandidateSetWorkerTest do
  use Lightning.DataCase

  import Mock

  alias Lightning.KafkaTriggers
  alias Lightning.KafkaTriggers.MessageCandidateSetServer
  alias Lightning.KafkaTriggers.MessageCandidateSetWorker
  alias Lightning.KafkaTriggers.TriggerKafkaMessage
  alias Lightning.WorkOrder

  setup_with_mocks([
    {KafkaTriggers, [], [send_after: fn pid, _msg, _time -> pid end]}
  ]) do
    :ok
  end

  describe ".start_link/1" do
    test "successfully starts the worker with empty state" do
      # with_mock KafkaTriggers,
      #   [
      #     
      #   ] do
        {:ok, pid} = MessageCandidateSetWorker.start_link([])

        assert :sys.get_state(pid) == []
      # end
    end

    test "queues a message to trigger a request to request a candidate set" do
      # with_mock KafkaTriggers,
      #   [
      #     send_after: fn pid, _msg, _time -> pid end
      #   ] do

        {:ok, pid} = MessageCandidateSetWorker.start_link([])

        assert_called(KafkaTriggers.send_after(pid, :request_candidate_set, 100))
      # end
    end
  end

  describe ".handle_info :requst_candidate_set - no candidate set available" do
    setup do
      {:ok, _pid} = MessageCandidateSetServer.start_link([])

      {:ok, pid} = MessageCandidateSetWorker.start_link([])

      %{
        pid: pid
      }
    end

    test "it enqueues a request to trigger the action after a delay", %{
      pid: pid
    } do
      pid |> Process.send(:request_candidate_set, [])

      assert_called(KafkaTriggers.send_after(pid, :request_candidate_set, 200))
    end
  end

  describe ".handle_info :request_candidate_set - candidate set available" do
    setup do
      message = insert(
        :trigger_kafka_message,
        key: "test-key",
        work_order: nil
      )

      {:ok, _pid} = MessageCandidateSetServer.start_link([])

      {:ok, pid} = MessageCandidateSetWorker.start_link([])

      %{
        message: message,
        pid: pid
      }
    end

    test "processes the candidate for the candidate set", %{
      message: message,
      pid: pid
    } do
      pid |> Process.send(:request_candidate_set, [])

      assert %{work_order: %WorkOrder{}} =
        TriggerKafkaMessage
        |> Repo.get(message.id, preload: :work_order)
    end
  end
end
