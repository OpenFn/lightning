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

  describe ".init/1 without worker count" do
    setup do
      pid = start_supervised!(MessageCandidateSetSupervisor)

      %{pid: pid}
    end

    test "starts server, and single worker", %{pid: pid} do
      assert [
               {
                 "mcs_worker_0",
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

  describe ".init/1 with worker count" do
    setup do
      pid =
        start_supervised!({MessageCandidateSetSupervisor, number_of_workers: 2})

      %{pid: pid}
    end

    test "starts server, and requested number of workers", %{pid: pid} do
      assert [
               {
                 "mcs_worker_1",
                 _w2_pid,
                 :worker,
                 [MessageCandidateSetWorker]
               },
               {
                 "mcs_worker_0",
                 _w1_pid,
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

  describe ".generate_worker_specs/1" do
    test "generates the requested number of worker specs" do
      no_set_delay =
        Lightning.Config.kafka_no_message_candidate_set_delay_milliseconds()

      next_set_delay =
        Lightning.Config.kafka_next_message_candidate_set_delay_milliseconds()

      assert no_set_delay != nil
      assert next_set_delay != nil

      expected = [
        Supervisor.child_spec(
          {
            MessageCandidateSetWorker,
            [no_set_delay: no_set_delay, next_set_delay: next_set_delay]
          },
          id: "mcs_worker_0"
        ),
        Supervisor.child_spec(
          {
            MessageCandidateSetWorker,
            [no_set_delay: no_set_delay, next_set_delay: next_set_delay]
          },
          id: "mcs_worker_1"
        )
      ]

      assert MessageCandidateSetSupervisor.generate_worker_specs(2) == expected
    end
  end
end
