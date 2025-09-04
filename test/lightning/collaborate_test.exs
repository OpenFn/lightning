defmodule Lightning.CollaborateTest do
  use Lightning.DataCase, async: false

  alias Lightning.Collaborate
  alias Lightning.Collaboration.Registry

  import Lightning.Factories
  import Eventually
  import Lightning.CollaborationHelpers

  setup do
    user = insert(:user)
    workflow = insert(:workflow)

    on_exit(fn ->
      ensure_doc_supervisor_stopped(workflow.id)
    end)

    {:ok, user: user, workflow: workflow}
  end

  describe "start/1" do
    test "starting a new collaboration with no existing SharedDoc", %{
      user: user,
      workflow: workflow
    } do
      assert {:ok, session_pid} =
               Collaborate.start(user: user, workflow_id: workflow.id)

      assert Process.alive?(session_pid)

      assert shared_doc_pid =
               Collaborate.whereis({:shared_doc, "workflow:#{workflow.id}"})

      assert Collaborate.whereis(
               {:persistence_writer, "workflow:#{workflow.id}"}
             )

      GenServer.stop(session_pid)

      refute_eventually(Process.alive?(session_pid))
      refute_eventually(Process.alive?(shared_doc_pid))
    end

    test "starting a new collaboration with an existing SharedDoc", %{
      user: user,
      workflow: workflow
    } do
      assert {:ok, session_1} =
               Collaborate.start(user: user, workflow_id: workflow.id)

      assert {:ok, session_2} =
               Collaborate.start(user: user, workflow_id: workflow.id)

      refute session_1 == session_2, "Same user and workflow get new sessions"

      process_group = Registry.get_group("workflow:#{workflow.id}")

      for {key, _} <- process_group do
        assert key in [
                 :doc_supervisor,
                 :persistence_writer,
                 :shared_doc,
                 :sessions
               ]
      end

      assert Registry.count("workflow:#{workflow.id}") == 5

      assert %{
               persistence_writer: persistence_writer_pid,
               shared_doc: shared_doc_pid
             } = Registry.get_group("workflow:#{workflow.id}")

      assert Process.alive?(persistence_writer_pid)
      assert Process.alive?(shared_doc_pid)

      shared_doc_state = :sys.get_state(shared_doc_pid)

      assert shared_doc_state.assigns.observer_process |> Map.keys() == [
               session_1,
               session_2
             ],
             "both sessions should be observers of the shared doc"

      GenServer.stop(session_1)
      GenServer.stop(session_2)

      refute_eventually(Process.alive?(session_1))
      refute_eventually(Process.alive?(session_2))
      refute_eventually(Process.alive?(shared_doc_pid))
    end
  end
end
