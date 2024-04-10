defmodule Lightning.KafkaTriggers.MessageCandidateSetSupervisorTest do
  use Lightning.DataCase, async: false

  alias Lightning.KafkaTriggers.MessageCandidateSetServer
  alias Lightning.KafkaTriggers.MessageCandidateSetSupervisor
  alias Lightning.KafkaTriggers.MessageCandidateSetWorker

  describe ".start_link/1" do
    test "successfully starts the supervisor" do
      assert _pid = start_supervised!(MessageCandidateSetSupervisor)
    end
  end

  describe ".init/1" do
    setup do
      pid = start_supervised!(MessageCandidateSetSupervisor)

      %{pid: pid}
    end

    test "starts the server and a single worker", %{pid: pid} do
      assert {:ok, _} = MessageCandidateSetSupervisor.init([])

      assert [
               {
                 MessageCandidateSetWorker,
                 _w_pid,
                 :worker,
                 [MessageCandidateSetWorker]
               },
               {
                 MessageCandidateSetServer,
                 _s_pid,
                 :worker,
                 [MessageCandidateSetServer]
               }
             ] = Supervisor.which_children(pid)
    end
  end
end
