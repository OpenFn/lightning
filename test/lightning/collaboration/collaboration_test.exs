defmodule Lightning.CollaborationTest do
  # Tests must be async: false because we put a SharedDoc in a dynamic supervisor
  # that isn't owned by the test process. So we need our Ecto sandbox to be
  # in shared mode.
  use Lightning.DataCase, async: false

  import Eventually

  alias Lightning.Collaboration.Session
  # we assume that the WorkflowCollaboration supervisor is up
  # that starts :pg with the :workflow_collaboration scope
  # and a dynamic supervisor called Lightning.WorkflowCollaboration

  describe "start/1" do
    test "when an existing SharedDoc doesn't exist" do
      workflow_id = Ecto.UUID.generate()

      {:ok, pid} = Session.start(workflow_id)

      # Wait a bit for the SharedDoc to be created asynchronously
      :timer.sleep(100)

      state = :sys.get_state(pid)
      assert state.workflow_id == workflow_id
      assert is_pid(state.shared_doc_pid)
    end

    test "when an existing SharedDoc does exist" do
      workflow_id = Ecto.UUID.generate()

      {:ok, pid1} = Session.start(workflow_id)
      state1 = :sys.get_state(pid1)

      # # Let SharedDoc start
      # :timer.sleep(100)

      {:ok, pid2} = Session.start(workflow_id)

      state2 = :sys.get_state(pid2)

      # Both should reference the same SharedDoc
      assert state1.shared_doc_pid == state2.shared_doc_pid
    end
  end

  describe "joining" do
    test "with start_link" do
      workflow_id = Ecto.UUID.generate()

      client_1 =
        Task.async(fn ->
          {:ok, pid} = Session.start(workflow_id)

          Session.get_document(pid) |> IO.inspect()

          pid
        end)

      client_1 = Task.await(client_1)

      client_2 =
        Task.async(fn ->
          {:ok, pid} = Session.start(workflow_id)

          Session.get_document(pid) |> IO.inspect()

          pid
        end)

      client_2 = Task.await(client_2)

      GenServer.stop(client_2)
      Process.alive?(client_2)

      GenServer.stop(client_1)
      Process.alive?(client_1)

      # TODO: I've enabled auto_exit: true, so this should be 0.
      # But we might want to control the cleanup ourselves.
      assert_eventually(
        length(:pg.get_members(:workflow_collaboration, workflow_id)) == 0
      )

      # IO.inspect({session_one, session_two})
    end
  end

  describe "teardown" do
    test "when a session is stopped" do
      workflow_id = Ecto.UUID.generate()

      {:ok, pid} = Session.start(workflow_id)
      %Session{shared_doc_pid: shared_doc_pid} = :sys.get_state(pid)

      Session.stop(pid)

      # SharedDoc should still be alive if we want to control cleanup

      refute_eventually Process.alive?(shared_doc_pid)

      # assert_eventually(
      #   :sys.get_state(shared_doc_pid)
      #   |> Map.get(:assigns)
      #   |> Map.get(:observer_process) ==
      #     %{}
      # )
    end
  end
end
