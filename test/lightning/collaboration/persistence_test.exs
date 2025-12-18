defmodule Lightning.Collaboration.PersistenceTest do
  use Lightning.DataCase, async: false

  alias Lightning.Collaboration.DocumentState
  alias Lightning.Collaboration.DocumentSupervisor
  alias Lightning.Collaboration.Registry

  import Lightning.Factories

  @moduledoc """
  Tests for Lightning.Collaboration.Persistence module.

  This module tests the persistence behavior that handles loading and
  reconciling Y.Doc state from the database when a DocumentSupervisor starts.
  """

  setup do
    Process.flag(:trap_exit, true)
    :ok
  end

  describe "reconcile_workflow_metadata/2" do
    setup do
      workflow = insert(:workflow)
      workflow_id = workflow.id
      document_name = "workflow:#{workflow_id}"

      {:ok,
       workflow: workflow, workflow_id: workflow_id, document_name: document_name}
    end

    test "converts deleted_at DateTime to string when reconciling", %{
      workflow: workflow,
      document_name: document_name
    } do
      # Create a workflow with a deleted_at timestamp
      workflow_with_deleted = %{workflow | deleted_at: DateTime.utc_now()}

      # Create persisted Y.Doc state with same lock_version
      doc = Yex.Doc.new()
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "initial_state", fn ->
        Yex.Map.set(workflow_map, "id", workflow.id)
        Yex.Map.set(workflow_map, "name", workflow.name)
        Yex.Map.set(workflow_map, "lock_version", workflow.lock_version)
        # Old persisted state has deleted_at as nil
        Yex.Map.set(workflow_map, "deleted_at", nil)
      end)

      {:ok, update_data} = Yex.encode_state_as_update(doc)

      {:ok, _} =
        Repo.insert(%DocumentState{
          document_name: document_name,
          state_data: update_data,
          version: :update
        })

      # Start DocumentSupervisor with workflow that has deleted_at
      # This triggers reconcile_workflow_metadata
      {:ok, doc_supervisor} =
        DocumentSupervisor.start_link(
          [workflow: workflow_with_deleted, document_name: document_name],
          name: Registry.via({:doc_supervisor, document_name})
        )

      assert Process.alive?(doc_supervisor)

      # Verify the deleted_at was properly converted to a string in Y.Doc
      shared_doc = Registry.whereis({:shared_doc, document_name})
      doc = Yex.Sync.SharedDoc.get_doc(shared_doc)
      reconciled_workflow_map = Yex.Doc.get_map(doc, "workflow")

      deleted_at_value = Yex.Map.fetch!(reconciled_workflow_map, "deleted_at")

      # Should be a string (ISO8601), not a DateTime struct
      assert is_binary(deleted_at_value)

      # Should match the original DateTime when parsed back
      assert {:ok, parsed_dt, _} = DateTime.from_iso8601(deleted_at_value)
      assert DateTime.compare(parsed_dt, workflow_with_deleted.deleted_at) == :eq

      # Clean up
      GenServer.stop(doc_supervisor, :normal)
    end

    test "handles nil deleted_at correctly", %{
      workflow: workflow,
      document_name: document_name
    } do
      # Workflow without deleted_at (nil)
      workflow_without_deleted = %{workflow | deleted_at: nil}

      # Create persisted state
      doc = Yex.Doc.new()
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "setup", fn ->
        Yex.Map.set(workflow_map, "id", workflow.id)
        Yex.Map.set(workflow_map, "name", workflow.name)
        Yex.Map.set(workflow_map, "lock_version", workflow.lock_version)
        Yex.Map.set(workflow_map, "deleted_at", nil)
      end)

      {:ok, update_data} = Yex.encode_state_as_update(doc)

      {:ok, _} =
        Repo.insert(%DocumentState{
          document_name: document_name,
          state_data: update_data,
          version: :update
        })

      # Start DocumentSupervisor
      {:ok, doc_supervisor} =
        DocumentSupervisor.start_link(
          [workflow: workflow_without_deleted, document_name: document_name],
          name: Registry.via({:doc_supervisor, document_name})
        )

      assert Process.alive?(doc_supervisor)

      # Verify deleted_at remains nil
      shared_doc = Registry.whereis({:shared_doc, document_name})
      doc = Yex.Sync.SharedDoc.get_doc(shared_doc)
      reconciled_workflow_map = Yex.Doc.get_map(doc, "workflow")

      deleted_at_value = Yex.Map.fetch!(reconciled_workflow_map, "deleted_at")
      assert deleted_at_value == nil

      # Clean up
      GenServer.stop(doc_supervisor, :normal)
    end

    test "reconciles lock_version when persisted state exists", %{
      workflow: workflow,
      document_name: document_name
    } do
      # Create persisted state with old lock_version
      old_lock_version = workflow.lock_version
      new_lock_version = old_lock_version + 1

      # Update workflow in DB to have new lock_version
      {:ok, updated_workflow} =
        workflow
        |> Ecto.Changeset.change(lock_version: new_lock_version)
        |> Repo.update()

      # Create persisted Y.Doc state with old lock_version
      doc = Yex.Doc.new()
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "setup", fn ->
        Yex.Map.set(workflow_map, "id", workflow.id)
        Yex.Map.set(workflow_map, "name", workflow.name)
        Yex.Map.set(workflow_map, "lock_version", old_lock_version)
        Yex.Map.set(workflow_map, "deleted_at", nil)
      end)

      {:ok, update_data} = Yex.encode_state_as_update(doc)

      {:ok, _} =
        Repo.insert(%DocumentState{
          document_name: document_name,
          state_data: update_data,
          version: :update
        })

      # Start DocumentSupervisor - should reconcile to new lock_version
      {:ok, doc_supervisor} =
        DocumentSupervisor.start_link(
          [workflow: updated_workflow, document_name: document_name],
          name: Registry.via({:doc_supervisor, document_name})
        )

      assert Process.alive?(doc_supervisor)

      # Verify lock_version was reconciled to the current DB value
      shared_doc = Registry.whereis({:shared_doc, document_name})
      doc = Yex.Sync.SharedDoc.get_doc(shared_doc)
      reconciled_workflow_map = Yex.Doc.get_map(doc, "workflow")

      reconciled_lock_version =
        Yex.Map.fetch!(reconciled_workflow_map, "lock_version")

      assert reconciled_lock_version == new_lock_version

      # Clean up
      GenServer.stop(doc_supervisor, :normal)
    end

    test "reconciles workflow name when it changed", %{
      workflow: workflow,
      document_name: document_name
    } do
      # Update workflow name in DB
      {:ok, updated_workflow} =
        workflow
        |> Ecto.Changeset.change(name: "Updated Name")
        |> Repo.update()

      # Create persisted state with old name
      doc = Yex.Doc.new()
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "setup", fn ->
        Yex.Map.set(workflow_map, "id", workflow.id)
        Yex.Map.set(workflow_map, "name", workflow.name)
        Yex.Map.set(workflow_map, "lock_version", workflow.lock_version)
        Yex.Map.set(workflow_map, "deleted_at", nil)
      end)

      {:ok, update_data} = Yex.encode_state_as_update(doc)

      {:ok, _} =
        Repo.insert(%DocumentState{
          document_name: document_name,
          state_data: update_data,
          version: :update
        })

      # Start DocumentSupervisor
      {:ok, doc_supervisor} =
        DocumentSupervisor.start_link(
          [workflow: updated_workflow, document_name: document_name],
          name: Registry.via({:doc_supervisor, document_name})
        )

      assert Process.alive?(doc_supervisor)

      # Verify name was reconciled
      shared_doc = Registry.whereis({:shared_doc, document_name})
      doc = Yex.Sync.SharedDoc.get_doc(shared_doc)
      reconciled_workflow_map = Yex.Doc.get_map(doc, "workflow")

      reconciled_name = Yex.Map.fetch!(reconciled_workflow_map, "name")
      assert reconciled_name == "Updated Name"

      # Clean up
      GenServer.stop(doc_supervisor, :normal)
    end
  end

  describe "bind/3 with no persisted state" do
    test "initializes workflow document from database" do
      workflow = insert(:workflow)
      document_name = "workflow:#{workflow.id}"

      # Don't create any persisted state - fresh start

      # Start DocumentSupervisor
      {:ok, doc_supervisor} =
        DocumentSupervisor.start_link(
          [workflow: workflow, document_name: document_name],
          name: Registry.via({:doc_supervisor, document_name})
        )

      assert Process.alive?(doc_supervisor)

      # Verify workflow was initialized from database
      shared_doc = Registry.whereis({:shared_doc, document_name})
      doc = Yex.Sync.SharedDoc.get_doc(shared_doc)
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      assert Yex.Map.fetch!(workflow_map, "id") == workflow.id
      assert Yex.Map.fetch!(workflow_map, "name") == workflow.name

      assert Yex.Map.fetch!(workflow_map, "lock_version") ==
               workflow.lock_version

      # Clean up
      GenServer.stop(doc_supervisor, :normal)
    end
  end

  describe "bind/3 with stale persisted state" do
    test "resets Y.Doc when persisted lock_version differs from database" do
      workflow = insert(:workflow, lock_version: 5)
      document_name = "workflow:#{workflow.id}"

      # Create persisted state with older lock_version
      doc = Yex.Doc.new()
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "setup", fn ->
        Yex.Map.set(workflow_map, "id", workflow.id)
        Yex.Map.set(workflow_map, "name", "Old Name")
        Yex.Map.set(workflow_map, "lock_version", 3)
        Yex.Map.set(workflow_map, "deleted_at", nil)
      end)

      {:ok, update_data} = Yex.encode_state_as_update(doc)

      {:ok, _} =
        Repo.insert(%DocumentState{
          document_name: document_name,
          state_data: update_data,
          version: :update
        })

      # Start DocumentSupervisor
      {:ok, doc_supervisor} =
        DocumentSupervisor.start_link(
          [workflow: workflow, document_name: document_name],
          name: Registry.via({:doc_supervisor, document_name})
        )

      assert Process.alive?(doc_supervisor)

      # Verify Y.Doc was reset to current database state
      shared_doc = Registry.whereis({:shared_doc, document_name})
      doc = Yex.Sync.SharedDoc.get_doc(shared_doc)
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      # Should have current lock_version, not the old one
      assert Yex.Map.fetch!(workflow_map, "lock_version") == 5
      # Should have current name, not the old one
      assert Yex.Map.fetch!(workflow_map, "name") == workflow.name

      # Clean up
      GenServer.stop(doc_supervisor, :normal)
    end
  end
end
