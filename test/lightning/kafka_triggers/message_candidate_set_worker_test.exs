defmodule Lightning.KafkaTriggers.MessageCandidateSetWorkerTest do
  use Lightning.DataCase

  import Mock

  alias Lightning.KafkaTriggers
  alias Lightning.KafkaTriggers.MessageCandidateSetWorker

  describe ".start_link/1" do
    test "successfully starts the worker with empty state" do
      with_mock KafkaTriggers,
        [
          send_after: fn pid, _msg, _time -> pid end
        ] do
        {:ok, pid} = MessageCandidateSetWorker.start_link([])

        assert :sys.get_state(pid) == []
      end
    end

    test "queues a message to trigger a request to request a candidate set" do
      with_mock KafkaTriggers,
        [
          send_after: fn pid, _msg, _time -> pid end
        ] do

        {:ok, pid} = MessageCandidateSetWorker.start_link([])

        assert_called(KafkaTriggers.send_after(pid, :request_candidate_set, 100))
      end
    end
  end
end
