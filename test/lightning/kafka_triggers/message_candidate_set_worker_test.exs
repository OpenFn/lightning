defmodule Lightning.KafkaTriggers.MessageCandidateSetWorkerTest do
  use Lightning.DataCase, async: false

  import Mock

  import Lightning.ApplicationHelpers, only: [dynamically_absorb_delay: 2]

  alias Lightning.KafkaTriggers
  alias Lightning.KafkaTriggers.MessageCandidateSetServer
  alias Lightning.KafkaTriggers.MessageCandidateSetWorker
  alias Lightning.KafkaTriggers.TriggerKafkaMessage
  alias Lightning.WorkOrder

  setup_with_mocks([
    {KafkaTriggers, [:passthrough], [send_after: fn pid, _msg, _time -> pid end]}
  ]) do
    :ok
  end

  describe ".start_link/1" do
    test "successfully starts the worker with empty state" do
      {:ok, pid} = start_supervised(MessageCandidateSetWorker)

      assert :sys.get_state(pid) == []
    end

    test "queues a message to trigger a request to request a candidate set" do
      {:ok, pid} = start_supervised(MessageCandidateSetWorker)

      assert_called(KafkaTriggers.send_after(pid, :request_candidate_set, 100))
    end
  end

  describe ".handle_info :requst_candidate_set - no candidate set available" do
    setup do
      {:ok, _server_pid} = start_supervised(MessageCandidateSetServer)

      {:ok, pid} = start_supervised(MessageCandidateSetWorker)

      %{
        pid: pid
      }
    end

    test "it enqueues a request to trigger the action after a delay", %{
      pid: pid
    } do
      pid |> Process.send(:request_candidate_set, [])

      dynamically_absorb_delay(fn -> :sys.get_state(pid) == [:called] end, [])

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

      {:ok, _server_pid} = start_supervised(MessageCandidateSetServer)

      {:ok, pid} = start_supervised(MessageCandidateSetWorker)

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

      dynamically_absorb_delay(fn -> :sys.get_state(pid) == [:called] end, [])

      assert %{work_order: %WorkOrder{}} =
        TriggerKafkaMessage
        |> Repo.get(message.id)
        |> Repo.preload(:work_order)
    end

    test "it enqueues a request to trigger the action after a delay", %{
      pid: pid
    } do
      pid |> Process.send(:request_candidate_set, [])

      dynamically_absorb_delay(fn -> :sys.get_state(pid) == [:called] end, [])

      assert_called_exactly(
        KafkaTriggers.send_after(pid, :request_candidate_set, 100),
        2
      )
    end
  end
end
