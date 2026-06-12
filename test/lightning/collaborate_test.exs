defmodule Lightning.CollaborateTest do
  use Lightning.DataCase, async: true

  alias Lightning.Collaborate
  alias Lightning.Collaboration.Registry

  import Lightning.Factories
  import Eventually
  import Lightning.CollaborationHelpers

  # Each test drives its own isolated collaboration tree (Registry,
  # DynamicSupervisor, and `:pg` scope), so concurrent tests can't see or
  # collide with each other's documents, sessions, or process-group members.
  # The instance is `start_supervised!`-owned, so the whole tree — including the
  # DB-writing SharedDoc/PersistenceWriter children — is torn down before this
  # test process (the sandbox owner) exits, avoiding a connection-checkin race.
  setup do
    instance = start_collaboration_instance()
    user = insert(:user)
    workflow = insert(:workflow)

    {:ok, instance: instance, user: user, workflow: workflow}
  end

  describe "start/2" do
    test "starting a new collaboration with no existing SharedDoc", %{
      instance: instance,
      user: user,
      workflow: workflow
    } do
      # Pre-start the document under an owner (self()) so its SharedDoc/
      # PersistenceWriter children can reach this test's sandbox connection (the
      # SharedDoc reads the DB during init). Collaborate.start/2 then reuses the
      # existing document rather than starting an unowned one. owner: self() also
      # ties the tree to this test for deterministic, flush-inclusive teardown.
      {:ok, _doc_supervisor} =
        start_collaboration_document(
          instance,
          workflow,
          "workflow:#{workflow.id}"
        )

      assert {:ok, session_pid} =
               Collaborate.start(instance, user: user, workflow: workflow)

      assert Process.alive?(session_pid)

      assert shared_doc_pid =
               Registry.whereis(
                 instance.registry,
                 {:shared_doc, "workflow:#{workflow.id}"}
               )

      assert Registry.whereis(
               instance.registry,
               {:persistence_writer, "workflow:#{workflow.id}"}
             )

      GenServer.stop(session_pid)

      refute_eventually(Process.alive?(session_pid))
      refute_eventually(Process.alive?(shared_doc_pid))
    end

    test "starting a new collaboration with an existing SharedDoc", %{
      instance: instance,
      user: user,
      workflow: workflow
    } do
      # Pre-start the document under an owner (self()) so its children can reach
      # this test's sandbox and the tree is torn down before the owner exits.
      # Collaborate.start/2 then reuses this existing document.
      {:ok, _doc_supervisor} =
        start_collaboration_document(
          instance,
          workflow,
          "workflow:#{workflow.id}"
        )

      assert {:ok, session_1} =
               Collaborate.start(instance, user: user, workflow: workflow)

      assert {:ok, session_2} =
               Collaborate.start(instance, user: user, workflow: workflow)

      refute session_1 == session_2, "Same user and workflow get new sessions"

      process_group =
        Registry.get_group(instance.registry, "workflow:#{workflow.id}")

      for {key, _} <- process_group do
        assert key in [
                 :doc_supervisor,
                 :persistence_writer,
                 :shared_doc,
                 :sessions
               ]
      end

      assert Registry.count(instance.registry, "workflow:#{workflow.id}") == 5

      assert %{
               persistence_writer: persistence_writer_pid,
               shared_doc: shared_doc_pid
             } = Registry.get_group(instance.registry, "workflow:#{workflow.id}")

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

    test "start_document/3 is idempotent for the same document", %{
      instance: instance,
      workflow: workflow
    } do
      document_name = "workflow:#{workflow.id}"

      # owner: self() (via the helper) ties the document tree to this test, so
      # its DB-writing children are stopped before the sandbox owner exits.
      assert {:ok, doc_supervisor_pid} =
               start_collaboration_document(instance, workflow, document_name)

      assert Process.alive?(doc_supervisor_pid)

      assert {:ok, ^doc_supervisor_pid} =
               Collaborate.start_document(instance, workflow, document_name)
    end

    test "start_document/4 with an owner self-terminates when the owner exits",
         %{instance: instance, workflow: workflow} do
      document_name = "workflow:#{workflow.id}"

      # A separate owner process we control, so the document tree's shutdown is
      # driven by this process exiting rather than by the test finishing. It is
      # also the pid threaded into the SharedDoc's init-time DB read (via
      # $callers), so grant it this test's sandbox connection first.
      owner = spawn(fn -> Process.sleep(:infinity) end)
      Ecto.Adapters.SQL.Sandbox.allow(Lightning.Repo, self(), owner)

      assert {:ok, doc_supervisor_pid} =
               Collaborate.start_document(instance, workflow, document_name,
                 owner: owner
               )

      doc_supervisor_ref = Process.monitor(doc_supervisor_pid)
      assert Process.alive?(doc_supervisor_pid)

      assert Registry.whereis(
               instance.registry,
               {:doc_supervisor, document_name}
             ) ==
               doc_supervisor_pid

      # Killing the owner stops the document tree with reason :normal, so
      # terminate/2 runs the flush and the :transient child isn't restarted.
      Process.exit(owner, :kill)

      assert_receive {:DOWN, ^doc_supervisor_ref, :process, ^doc_supervisor_pid,
                      :normal},
                     5000

      refute_eventually(
        Registry.whereis(instance.registry, {:doc_supervisor, document_name})
      )

      refute_eventually(
        Registry.whereis(instance.registry, {:shared_doc, document_name})
      )

      refute_eventually(
        Registry.whereis(
          instance.registry,
          {:persistence_writer, document_name}
        )
      )
    end

    test "start_document monitors only the given owner (production default = none)",
         %{instance: instance, workflow: workflow} do
      document_name = "workflow:#{workflow.id}"

      # Start the document under this test as owner. The owner field is both the
      # monitor target and (in tests) the pid the SharedDoc's init-time DB read
      # is threaded through, so a real owner is what lets the tree start under an
      # async sandbox at all.
      {:ok, doc_supervisor_pid} =
        start_collaboration_document(instance, workflow, document_name)

      # With an explicit owner, a monitor is set up keyed to that owner.
      assert is_reference(:sys.get_state(doc_supervisor_pid).owner_ref)

      # The production default is the no-owner 3-arity: a second call without an
      # owner is idempotent and reuses the existing tree — it does not impose a
      # new monitor — so a production document outlives whoever re-requests it.
      assert {:ok, ^doc_supervisor_pid} =
               Collaborate.start_document(instance, workflow, document_name)

      assert is_reference(:sys.get_state(doc_supervisor_pid).owner_ref)
    end
  end
end
