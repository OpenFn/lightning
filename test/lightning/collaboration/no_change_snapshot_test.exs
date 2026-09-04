defmodule Lightning.Collaboration.NoChangeSnapshotTest do
  @moduledoc """
  Tests to reproduce and verify the fix for phantom snapshot creation
  when no actual changes are made to a workflow.
  """
  use Lightning.DataCase, async: true

  import Lightning.Factories
  import Lightning.CollaborationHelpers

  alias Lightning.Collaboration.Session
  alias Lightning.Workflows

  describe "saving without changes" do
    setup do
      # Each test drives its own isolated collaboration tree (Registry,
      # DynamicSupervisor, and `:pg` scope), so concurrent tests can't see each
      # other's documents.
      #
      # Stub the broadcast calls that save_workflow makes. save_workflow runs in
      # the Session process; tests that exercise it allow that process into this
      # test's mocks/sandbox, and the DocumentSupervisor's spawned children are
      # granted access by the owner-anchored startup hook via `owner: self()`.
      Mox.stub(LightningMock, :broadcast, fn _topic, _message -> :ok end)

      instance = start_collaboration_instance()

      user = insert(:user)
      project = insert(:project)
      workflow = insert(:workflow, name: "Test Workflow", project: project)
      job = insert(:job, workflow: workflow, name: "Test Job")

      %{
        instance: instance,
        user: user,
        project: project,
        workflow: workflow,
        job: job
      }
    end

    test "does not create snapshot when saving Y.Doc with no changes", %{
      instance: instance,
      user: user,
      workflow: workflow
    } do
      session_pid = start_session(instance, workflow, user)

      # Get initial lock_version
      workflow = Workflows.get_workflow!(workflow.id)
      initial_lock_version = workflow.lock_version

      # Count initial snapshots
      initial_snapshot_count = snapshot_count(workflow.id)

      # Save without making any changes to the Y.Doc
      {:ok, saved_workflow} = Session.save_workflow(session_pid, user)

      # Verify no snapshot was created
      final_snapshot_count = snapshot_count(workflow.id)

      assert saved_workflow.lock_version == initial_lock_version,
             "Lock version should not increment without changes"

      assert final_snapshot_count == initial_snapshot_count,
             "No new snapshot should be created without changes"
    end

    test "creates snapshot when actually changing workflow data", %{
      instance: instance,
      user: user,
      workflow: workflow
    } do
      session_pid = start_session(instance, workflow, user)

      # Get initial lock_version
      workflow = Workflows.get_workflow!(workflow.id)
      initial_lock_version = workflow.lock_version

      # Count initial snapshots
      initial_snapshot_count = snapshot_count(workflow.id)

      # Make a real change to the workflow
      doc = Session.get_doc(session_pid)
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "test_change", fn ->
        Yex.Map.set(workflow_map, "name", "Changed Name")
      end)

      # Save with changes
      {:ok, saved_workflow} = Session.save_workflow(session_pid, user)

      # Verify snapshot WAS created
      final_snapshot_count = snapshot_count(workflow.id)

      assert saved_workflow.lock_version == initial_lock_version + 1,
             "Lock version should increment with changes"

      assert final_snapshot_count == initial_snapshot_count + 1,
             "New snapshot should be created with changes"
    end

    test "round-trip deserialization produces empty changeset", %{
      workflow: workflow
    } do
      # Load with associations
      workflow =
        Workflows.get_workflow!(workflow.id, include: [:jobs, :edges, :triggers])

      # Serialize to Y.Doc
      doc = Yex.Doc.new()
      Lightning.Collaboration.WorkflowSerializer.serialize_to_ydoc(doc, workflow)

      # Deserialize
      deserialized =
        Lightning.Collaboration.WorkflowSerializer.deserialize_from_ydoc(
          doc,
          workflow.id
        )

      # Create changeset
      changeset = Workflows.change_workflow(workflow, deserialized)

      # Verify no changes detected
      assert changeset.changes == %{},
             "Round-trip serialization should not create phantom changes"
    end
  end

  # Start the document under the isolated instance (owner: self() ties its
  # lifetime to this test) and a Session that joins it, granting that Session
  # the per-test sandbox/mock access it needs to save.
  defp start_session(instance, workflow, user) do
    document_name = "workflow:#{workflow.id}"

    {:ok, _doc_supervisor} =
      start_collaboration_document(instance, workflow, document_name)

    session_pid =
      start_supervised!(
        {Session,
         workflow: workflow,
         user: user,
         document_name: document_name,
         registry: instance.registry,
         pg_scope: instance.pg_scope}
      )

    allow_collaboration_process(session_pid)

    session_pid
  end

  defp snapshot_count(workflow_id) do
    Lightning.Repo.all(
      from s in Lightning.Workflows.Snapshot,
        where: s.workflow_id == ^workflow_id
    )
    |> length()
  end
end
