defmodule Lightning.KafkaTriggers.MessageCandidateSetWorkerTest do
  use Lightning.DataCase

  alias Lightning.KafkaTriggers.MessageCandidateSetWorker

  describe ".start_link/1" do
    test "successfully starts the worker with empty state" do
      {:ok, pid} = MessageCandidateSetWorker.start_link([])

      assert :sys.get_state(pid) == []
    end
  end
end
