defmodule Lightning.Collaboration.NoChangeSnapshotTest do
  @moduledoc """
  Tests to reproduce and verify the fix for phantom snapshot creation
  when no actual changes are made to a workflow.
  """
  use Lightning.DataCase, async: false

  import Lightning.Factories

  alias Lightning.Collaboration.{DocumentSupervisor, Session}
  alias Lightning.Workflows

  describe "saving without changes" do
    setup do
      # Set global mode for the mock to allow cross-process calls
      Mox.set_mox_global(LightningMock)
      # Stub the broadcast calls that save_workflow makes
      Mox.stub(LightningMock, :broadcast, fn _topic, _message -> :ok end)

      user = insert(:user)
      project = insert(:project)
      workflow = insert(:workflow, name: "Test Workflow", project: project)
      job = insert(:job, workflow: workflow, name: "Test Job")

      %{user: user, project: project, workflow: workflow, job: job}
    end

    test "does not create snapshot when saving Y.Doc with no changes", %{
      user: user,
      workflow: workflow
    } do
      # Start document and session
      start_supervised!(
        {DocumentSupervisor,
         workflow: workflow, document_name: "workflow:#{workflow.id}"}
      )

      session_pid =
        start_supervised!(
          {Session,
           workflow: workflow,
           user: user,
           document_name: "workflow:#{workflow.id}"}
        )

      # Get initial lock_version
      workflow = Workflows.get_workflow!(workflow.id)
      initial_lock_version = workflow.lock_version

      # Count initial snapshots
      initial_snapshot_count =
        Lightning.Repo.all(
          from s in Lightning.Workflows.Snapshot,
            where: s.workflow_id == ^workflow.id
        )
        |> length()

      # Save without making any changes to the Y.Doc
      {:ok, saved_workflow} = Session.save_workflow(session_pid, user)

      # Verify no snapshot was created
      final_snapshot_count =
        Lightning.Repo.all(
          from s in Lightning.Workflows.Snapshot,
            where: s.workflow_id == ^workflow.id
        )
        |> length()

      assert saved_workflow.lock_version == initial_lock_version,
             "Lock version should not increment without changes"

      assert final_snapshot_count == initial_snapshot_count,
             "No new snapshot should be created without changes"
    end

    test "creates snapshot when actually changing workflow data", %{
      user: user,
      workflow: workflow
    } do
      # Start document and session
      start_supervised!(
        {DocumentSupervisor,
         workflow: workflow, document_name: "workflow:#{workflow.id}"}
      )

      session_pid =
        start_supervised!(
          {Session,
           workflow: workflow,
           user: user,
           document_name: "workflow:#{workflow.id}"}
        )

      # Get initial lock_version
      workflow = Workflows.get_workflow!(workflow.id)
      initial_lock_version = workflow.lock_version

      # Count initial snapshots
      initial_snapshot_count =
        Lightning.Repo.all(
          from s in Lightning.Workflows.Snapshot,
            where: s.workflow_id == ^workflow.id
        )
        |> length()

      # Make a real change to the workflow
      doc = Session.get_doc(session_pid)
      workflow_map = Yex.Doc.get_map(doc, "workflow")

      Yex.Doc.transaction(doc, "test_change", fn ->
        Yex.Map.set(workflow_map, "name", "Changed Name")
      end)

      # Save with changes
      {:ok, saved_workflow} = Session.save_workflow(session_pid, user)

      # Verify snapshot WAS created
      final_snapshot_count =
        Lightning.Repo.all(
          from s in Lightning.Workflows.Snapshot,
            where: s.workflow_id == ^workflow.id
        )
        |> length()

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
end
