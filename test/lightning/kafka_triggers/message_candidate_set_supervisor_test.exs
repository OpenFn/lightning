defmodule Lightning.KafkaTriggers.MessageCandidateSetSupervisorTest do
  use Lightning.DataCase, async: false

  alias Lightning.KafkaTriggers.MessageServer
  alias Lightning.KafkaTriggers.MessageCandidateSetServer
  alias Lightning.KafkaTriggers.MessageCandidateSetSupervisor
  alias Lightning.KafkaTriggers.MessageCandidateSetWorker
  alias Lightning.KafkaTriggers.MessageWorker

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

    test "starts single server and single worker per type", %{pid: pid} do
      assert [
               {
                 "message_worker_0",
                 _w2_pid,
                 :worker,
                 [MessageWorker]
               },
               {
                 MessageServer,
                 _s2_pid,
                 :worker,
                 [MessageServer]
               },
               {
                 "mcs_worker_0",
                 _w1_pid,
                 :worker,
                 [MessageCandidateSetWorker]
               },
               {
                 MessageCandidateSetServer,
                 _s1_pid,
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
                 "message_worker_1",
                 _w4_pid,
                 :worker,
                 [MessageWorker]
               },
               {
                 "message_worker_0",
                 _w3_pid,
                 :worker,
                 [MessageWorker]
               },
               {
                 MessageServer,
                 _s2_pid,
                 :worker,
                 [MessageServer]
               },
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
                 _s1_pid,
                 :worker,
                 [MessageCandidateSetServer]
               }
             ] = Supervisor.which_children(pid)
    end
  end

  describe "generate_child_specs/2 - MessageCandidateSetServer" do
    test "generates server spec and requested number of worker specs" do
      no_set_delay =
        Application.get_env(:lightning, :kafka_triggers)[
          :no_message_candidate_set_delay_milliseconds
        ]

      next_set_delay =
        Application.get_env(:lightning, :kafka_triggers)[
          :next_message_candidate_set_delay_milliseconds
        ]

      assert no_set_delay != nil
      assert next_set_delay != nil

      expected = [
        MessageCandidateSetServer,
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

      result =
        MessageCandidateSetServer
        |> MessageCandidateSetSupervisor.generate_child_specs(2)

      assert result == expected
    end
  end

  describe "generate_child_specs/2 - MessageServer" do
    test "generates server spec and requested number of worker specs" do
      no_set_delay =
        Application.get_env(:lightning, :kafka_triggers)[
          :no_message_candidate_set_delay_milliseconds
        ]

      next_set_delay =
        Application.get_env(:lightning, :kafka_triggers)[
          :next_message_candidate_set_delay_milliseconds
        ]

      assert no_set_delay != nil
      assert next_set_delay != nil

      expected = [
        MessageServer,
        Supervisor.child_spec(
          {
            MessageWorker,
            [no_set_delay: no_set_delay, next_set_delay: next_set_delay]
          },
          id: "message_worker_0"
        ),
        Supervisor.child_spec(
          {
            MessageWorker,
            [no_set_delay: no_set_delay, next_set_delay: next_set_delay]
          },
          id: "message_worker_1"
        )
      ]

      result =
        MessageServer
        |> MessageCandidateSetSupervisor.generate_child_specs(2)

      assert result == expected
    end
  end
end
