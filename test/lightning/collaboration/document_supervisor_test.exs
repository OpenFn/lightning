defmodule Lightning.Collaboration.DocumentSupervisorTest do
  use Lightning.DataCase, async: false

  alias Lightning.Collaboration.DocumentSupervisor
  alias Lightning.Collaboration.PersistenceWriter
  alias Lightning.Collaboration.Registry, as: CollabRegistry

  import Eventually
  import Lightning.Factories

  describe "start_link/1" do
    test "starts supervisor with required workflow_id" do
      workflow = insert(:workflow)

      pid = start_supervised!({DocumentSupervisor, workflow_id: workflow.id})

      assert Process.alive?(pid)

      # Verify it's registered in the Registry
      assert [{^pid, _}] =
               Registry.lookup(
                 CollabRegistry,
                 {:doc_supervisor, workflow.id}
               )
    end

    test "fails without workflow_id" do
      assert_raise KeyError, fn ->
        DocumentSupervisor.start_link([])
      end
    end

    test "prevents duplicate supervisors for same workflow" do
      workflow = insert(:workflow)

      assert {:ok, pid1} =
               DocumentSupervisor.start_link(workflow_id: workflow.id)

      assert {:error, {:already_started, _}} =
               DocumentSupervisor.start_link(workflow_id: workflow.id)

      Process.exit(pid1, :normal)
    end
  end

  describe "supervised children" do
    setup do
      workflow = insert(:workflow)

      supervisor_pid =
        start_supervised!({DocumentSupervisor, workflow_id: workflow.id})

      %{workflow: workflow, supervisor_pid: supervisor_pid}
    end

    test "starts PersistenceWriter as child", %{workflow: workflow} do
      document_name = "workflow:#{workflow.id}"

      # PersistenceWriter should be registered
      assert writer_pid =
               CollabRegistry.whereis({:persistence_writer, document_name})

      assert Process.alive?(writer_pid)

      # Verify it's actually a PersistenceWriter
      assert state = :sys.get_state(writer_pid)

      assert %PersistenceWriter{document_name: ^document_name} = state
    end

    test "starts SharedDoc as child", %{workflow: workflow} do
      document_name = "workflow:#{workflow.id}"

      assert_eventually(fn ->
        doc_pid = CollabRegistry.whereis({:shared_doc, document_name})

        doc_pid && Process.alive?(doc_pid)
      end)
    end

    test "SharedDoc receives persistence opts with workflow_id", %{
      workflow: workflow
    } do
      document_name = "workflow:#{workflow.id}"

      assert_eventually(fn ->
        doc_pid = CollabRegistry.whereis({:shared_doc, document_name})

        if doc_pid do
          Process.alive?(doc_pid)
        else
          false
        end
      end)

      assert doc_pid = CollabRegistry.whereis({:shared_doc, document_name})

      # The SharedDoc should have the persistence module configured
      assert %{assigns: %{persistence: Lightning.Collaboration.Persistence}} =
               :sys.get_state(doc_pid)
    end
  end

  describe "rest_for_one strategy" do
    setup do
      workflow = insert(:workflow)

      supervisor_pid =
        start_supervised!({DocumentSupervisor, workflow_id: workflow.id})

      %{
        workflow: workflow,
        supervisor_pid: supervisor_pid
        # document_name: document_name
      }
    end

    test "restarts SharedDoc if it crashes", %{document_name: document_name} do
      # Get initial SharedDoc pid
      {:ok, doc_pid} = Yex.Sync.Registry.lookup(document_name)

      # Kill SharedDoc
      Process.exit(doc_pid, :kill)

      # Wait for restart
      Process.sleep(100)

      # Should have a new SharedDoc
      {:ok, new_doc_pid} = Yex.Sync.Registry.lookup(document_name)
      assert Process.alive?(new_doc_pid)
      assert new_doc_pid != doc_pid
    end

    test "restarts both children if PersistenceWriter crashes", %{
      document_name: document_name
    } do
      # Get initial pids
      [{writer_pid, _}] =
        Registry.lookup(
          CollabRegistry,
          {:persistence_writer, document_name}
        )

      {:ok, doc_pid} = Yex.Sync.Registry.lookup(document_name)

      # Kill PersistenceWriter (first child)
      Process.exit(writer_pid, :kill)

      # Wait for restart
      Process.sleep(200)

      # Both should have new pids (rest_for_one strategy)
      [{new_writer_pid, _}] =
        Registry.lookup(
          CollabRegistry,
          {:persistence_writer, document_name}
        )

      {:ok, new_doc_pid} = Yex.Sync.Registry.lookup(document_name)

      assert Process.alive?(new_writer_pid)
      assert Process.alive?(new_doc_pid)
      assert new_writer_pid != writer_pid
      assert new_doc_pid != doc_pid
    end
  end

  describe "supervisor termination" do
    test "cleans up all children when supervisor stops" do
      workflow = insert(:workflow)
      document_name = "workflow:#{workflow.id}"

      {:ok, supervisor_pid} =
        DocumentSupervisor.start_link(workflow_id: workflow.id)

      # Get child pids
      [{writer_pid, _}] =
        Registry.lookup(
          CollabRegistry,
          {:persistence_writer, document_name}
        )

      {:ok, doc_pid} = Yex.Sync.Registry.lookup(document_name)

      # Stop supervisor
      Process.exit(supervisor_pid, :normal)
      Process.sleep(100)

      # Children should be gone
      refute Process.alive?(writer_pid)
      refute Process.alive?(doc_pid)

      # Registry entries should be cleaned up
      assert [] =
               Registry.lookup(
                 CollabRegistry,
                 {:persistence_writer, document_name}
               )

      assert {:error, :not_found} = Yex.Sync.Registry.lookup(document_name)
    end
  end

  describe "via tuple registration" do
    test "supervisor is accessible via Registry" do
      workflow = insert(:workflow)

      {:ok, pid} = DocumentSupervisor.start_link(workflow_id: workflow.id)

      # Should be able to send messages via the registered name
      via_name =
        {:via, Registry, {CollabRegistry, {:doc_supervisor, workflow.id}}}

      assert Process.whereis(elem(via_name, 2)) == pid

      Process.exit(pid, :normal)
    end
  end
end
