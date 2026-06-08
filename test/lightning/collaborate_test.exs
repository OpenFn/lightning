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
               Collaborate.start(user: user, workflow: workflow)

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
               Collaborate.start(user: user, workflow: workflow)

      assert {:ok, session_2} =
               Collaborate.start(user: user, workflow: workflow)

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

    test "start_document/2 is idempotent for the same document", %{
      workflow: workflow
    } do
      document_name = "workflow:#{workflow.id}"

      assert {:ok, doc_supervisor_pid} =
               Collaborate.start_document(workflow, document_name)

      assert Process.alive?(doc_supervisor_pid)

      assert {:ok, ^doc_supervisor_pid} =
               Collaborate.start_document(workflow, document_name)
    end

    test "start_document/3 with an owner self-terminates when the owner exits",
         %{workflow: workflow} do
      document_name = "workflow:#{workflow.id}"

      # A separate owner process we control, so the document tree's shutdown is
      # driven by this process exiting rather than by the test finishing.
      owner = spawn(fn -> Process.sleep(:infinity) end)

      assert {:ok, doc_supervisor_pid} =
               Collaborate.start_document(workflow, document_name, owner: owner)

      doc_supervisor_ref = Process.monitor(doc_supervisor_pid)
      assert Process.alive?(doc_supervisor_pid)

      assert Registry.whereis({:doc_supervisor, document_name}) ==
               doc_supervisor_pid

      # Killing the owner stops the document tree with reason :normal, so
      # terminate/2 runs the flush and the :transient child isn't restarted.
      Process.exit(owner, :kill)

      assert_receive {:DOWN, ^doc_supervisor_ref, :process, ^doc_supervisor_pid,
                      :normal},
                     5000

      refute_eventually(Registry.whereis({:doc_supervisor, document_name}))
      refute_eventually(Registry.whereis({:shared_doc, document_name}))
      refute_eventually(Registry.whereis({:persistence_writer, document_name}))
    end

    test "start_document/3 without an owner does not monitor (production default)",
         %{workflow: workflow} do
      document_name = "workflow:#{workflow.id}"

      assert {:ok, doc_supervisor_pid} =
               Collaborate.start_document(workflow, document_name)

      assert :sys.get_state(doc_supervisor_pid).owner_ref == nil

      Collaborate.stop_document(document_name)
    end
  end
end
