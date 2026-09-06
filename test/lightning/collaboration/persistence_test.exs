defmodule Lightning.Collaboration.PersistenceTest do
  use Lightning.DataCase, async: true

  alias Lightning.Collaboration.DocumentState
  alias Lightning.Collaboration.DocumentSupervisor
  alias Lightning.Collaboration.Registry

  import Lightning.Factories
  import Lightning.CollaborationHelpers

  @moduledoc """
  Tests for Lightning.Collaboration.Persistence module.

  This module tests the persistence behavior that handles loading and
  reconciling Y.Doc state from the database when a DocumentSupervisor starts.
  """

  # Each test drives its own isolated collaboration tree (Registry,
  # DynamicSupervisor, and `:pg` scope), so concurrent tests can't collide on
  # the application-wide singletons. Documents are started under that tree with
  # `owner: self()`, which (a) lets the SharedDoc's init-time DB read and the
  # children's later writes reach this test's sandbox connection, and (b) ties
  # the tree's lifetime to this test. The instance supervisor is
  # `start_supervised!`-owned, so its DB-writing children are stopped — flush
  # included via DocumentSupervisor.terminate/2 — before this test process (the
  # sandbox owner) exits, even if an assertion raises first.
  setup do
    Process.flag(:trap_exit, true)
    instance = start_collaboration_instance()
    {:ok, instance: instance}
  end

  # Start a DocumentSupervisor under the test's isolated instance. owner: self()
  # threads this test's sandbox/mock access into the spawned SharedDoc and
  # PersistenceWriter (and into the SharedDoc's init-time read via the
  # persistence state).
  #
  # Started under `start_supervised!` so ExUnit owns it: on test exit ExUnit
  # synchronously stops it, running DocumentSupervisor.terminate/2 (which flushes
  # the PersistenceWriter through the SharedDoc) to completion. That teardown is
  # registered after DataCase's `stop_owner` and runs LIFO, so it executes while
  # the sandbox owner is still alive — no DB-writing child is left mid-query when
  # the connection is checked back in.
  defp start_document(instance, workflow, document_name) do
    start_supervised!(
      {DocumentSupervisor,
       workflow: workflow,
       document_name: document_name,
       registry: instance.registry,
       pg_scope: instance.pg_scope,
       owner: self(),
       name: Registry.via(instance.registry, {:doc_supervisor, document_name})}
    )
  end

  defp shared_doc_map(instance, document_name) do
    shared_doc =
      Registry.whereis(instance.registry, {:shared_doc, document_name})

    doc = Yex.Sync.SharedDoc.get_doc(shared_doc)
    Yex.Doc.get_map(doc, "workflow")
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
      instance: instance,
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
      doc_supervisor =
        start_document(instance, workflow_with_deleted, document_name)

      assert Process.alive?(doc_supervisor)

      # Verify the deleted_at was properly converted to a string in Y.Doc
      reconciled_workflow_map = shared_doc_map(instance, document_name)

      deleted_at_value = Yex.Map.fetch!(reconciled_workflow_map, "deleted_at")

      # Should be a string (ISO8601), not a DateTime struct
      assert is_binary(deleted_at_value)

      # Should match the original DateTime when parsed back
      assert {:ok, parsed_dt, _} = DateTime.from_iso8601(deleted_at_value)
      assert DateTime.compare(parsed_dt, workflow_with_deleted.deleted_at) == :eq
    end

    test "handles nil deleted_at correctly", %{
      instance: instance,
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
      doc_supervisor =
        start_document(instance, workflow_without_deleted, document_name)

      assert Process.alive?(doc_supervisor)

      # Verify deleted_at remains nil
      reconciled_workflow_map = shared_doc_map(instance, document_name)

      deleted_at_value = Yex.Map.fetch!(reconciled_workflow_map, "deleted_at")
      assert deleted_at_value == nil
    end

    test "reconciles lock_version when persisted state exists", %{
      instance: instance,
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
      doc_supervisor = start_document(instance, updated_workflow, document_name)

      assert Process.alive?(doc_supervisor)

      # Verify lock_version was reconciled to the current DB value
      reconciled_workflow_map = shared_doc_map(instance, document_name)

      reconciled_lock_version =
        Yex.Map.fetch!(reconciled_workflow_map, "lock_version")

      assert reconciled_lock_version == new_lock_version
    end

    test "reconciles workflow name when it changed", %{
      instance: instance,
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
      doc_supervisor = start_document(instance, updated_workflow, document_name)

      assert Process.alive?(doc_supervisor)

      # Verify name was reconciled
      reconciled_workflow_map = shared_doc_map(instance, document_name)

      reconciled_name = Yex.Map.fetch!(reconciled_workflow_map, "name")
      assert reconciled_name == "Updated Name"
    end
  end

  describe "bind/3 with no persisted state" do
    test "initializes workflow document from database", %{instance: instance} do
      workflow = insert(:workflow)
      document_name = "workflow:#{workflow.id}"

      # Don't create any persisted state - fresh start

      # Start DocumentSupervisor
      doc_supervisor = start_document(instance, workflow, document_name)

      assert Process.alive?(doc_supervisor)

      # Verify workflow was initialized from database
      workflow_map = shared_doc_map(instance, document_name)

      assert Yex.Map.fetch!(workflow_map, "id") == workflow.id
      assert Yex.Map.fetch!(workflow_map, "name") == workflow.name

      assert Yex.Map.fetch!(workflow_map, "lock_version") ==
               workflow.lock_version
    end
  end

  describe "bind/3 with stale persisted state" do
    test "resets Y.Doc when persisted lock_version differs from database", %{
      instance: instance
    } do
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
      doc_supervisor = start_document(instance, workflow, document_name)

      assert Process.alive?(doc_supervisor)

      # Verify Y.Doc was reset to current database state
      workflow_map = shared_doc_map(instance, document_name)

      # Should have current lock_version, not the old one
      assert Yex.Map.fetch!(workflow_map, "lock_version") == 5
      # Should have current name, not the old one
      assert Yex.Map.fetch!(workflow_map, "name") == workflow.name
    end
  end
end
