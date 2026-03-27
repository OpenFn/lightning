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
    test "loads persisted state as-is without reconciliation" do
      workflow = insert(:workflow, lock_version: 5)
      document_name = "workflow:#{workflow.id}"

      # Create persisted state with an older lock_version and different name
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

      # Persisted state is loaded as-is — no automatic reconciliation
      shared_doc = Registry.whereis({:shared_doc, document_name})
      doc = Yex.Sync.SharedDoc.get_doc(shared_doc)
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      assert Yex.Map.fetch!(workflow_map, "lock_version") == 3.0
      assert Yex.Map.fetch!(workflow_map, "name") == "Old Name"

      # Clean up
      GenServer.stop(doc_supervisor, :normal)
    end
  end
end
