defmodule Lightning.Collaboration.ReconcileWorkflowDocumentTest do
  use Lightning.DataCase, async: false

  import Lightning.Factories
  import Lightning.CollaborationHelpers
  import Eventually

  alias Lightning.Collaborate
  alias Lightning.Collaboration.Session
  alias Lightning.Collaboration.WorkflowReconciler
  alias Lightning.Projects.Sandboxes
  alias Lightning.Workflows

  setup do
    Mox.set_mox_global(LightningMock)

    user = insert(:user)
    {:ok, user: user}
  end

  describe "reconcile_workflow_document/1" do
    setup do
      workflow = insert(:complex_workflow)
      on_exit(fn -> ensure_doc_supervisor_stopped(workflow.id) end)
      %{workflow: workflow}
    end

    test "resyncs a live document to the current database state", %{
      user: user,
      workflow: workflow
    } do
      {:ok, session_pid} = Collaborate.start(workflow: workflow, user: user)
      shared_doc = Session.get_doc(session_pid)
      workflow_map = Yex.Doc.get_map(shared_doc, "workflow")

      original_name = Yex.Map.fetch!(workflow_map, "name")

      {:ok, updated} =
        workflow
        |> Ecto.Changeset.change(%{name: "Renamed out of band"})
        |> Ecto.Changeset.optimistic_lock(:lock_version)
        |> Repo.update()

      assert Yex.Map.fetch!(workflow_map, "name") == original_name

      assert :ok = WorkflowReconciler.reconcile_workflow_document(workflow.id)

      db_job_count =
        Workflows.get_workflow(workflow.id, include: [:jobs]).jobs |> length()

      jobs_array = Yex.Doc.get_array(shared_doc, "jobs")

      assert Yex.Map.fetch!(workflow_map, "name") == "Renamed out of band"
      assert Yex.Map.fetch!(workflow_map, "lock_version") == updated.lock_version
      assert Yex.Array.length(jobs_array) == db_job_count
    end

    test "is a no-op when no live document exists for the workflow", %{
      workflow: workflow
    } do
      assert WorkflowReconciler.reconcile_workflow_document(workflow.id) == :ok
    end
  end

  describe "ReconcileRequested broadcast" do
    setup do
      workflow = insert(:complex_workflow)
      on_exit(fn -> ensure_doc_supervisor_stopped(workflow.id) end)
      %{workflow: workflow}
    end

    test "the document owner reconciles when the event is published", %{
      user: user,
      workflow: workflow
    } do
      {:ok, session_pid} = Collaborate.start(workflow: workflow, user: user)
      shared_doc = Session.get_doc(session_pid)
      workflow_map = Yex.Doc.get_map(shared_doc, "workflow")

      {:ok, updated} =
        workflow
        |> Ecto.Changeset.change(%{name: "Updated via event"})
        |> Ecto.Changeset.optimistic_lock(:lock_version)
        |> Repo.update()

      assert :ok = WorkflowReconciler.request_reconciliation(workflow.id)

      assert_eventually(
        Yex.Map.fetch!(workflow_map, "lock_version") == updated.lock_version
      )

      assert Yex.Map.fetch!(workflow_map, "name") == "Updated via event"
    end
  end

  describe "Sandboxes.merge/4" do
    test "reconciles the parent's live document with merged content", %{
      user: user
    } do
      parent = insert(:project, project_users: [%{user: user, role: :owner}])
      parent_wf = insert(:workflow, project: parent, name: "PromoteFlow")

      trigger =
        insert(:trigger, workflow: parent_wf, type: :webhook, enabled: false)

      parent_job =
        insert(:job, workflow: parent_wf, name: "J1", body: "fn(s => s);")

      insert(:edge,
        workflow: parent_wf,
        source_trigger_id: trigger.id,
        target_job_id: parent_job.id,
        condition_type: :always
      )

      parent_wf = Workflows.get_workflow(parent_wf.id)
      on_exit(fn -> ensure_doc_supervisor_stopped(parent_wf.id) end)

      {:ok, sandbox} =
        Sandboxes.provision(parent, user, %{name: "promote-sandbox"})

      {:ok, session_pid} = Collaborate.start(workflow: parent_wf, user: user)
      shared_doc = Session.get_doc(session_pid)
      workflow_map = Yex.Doc.get_map(shared_doc, "workflow")
      initial_lock_version = Yex.Map.fetch!(workflow_map, "lock_version")

      sandbox_job =
        sandbox
        |> Repo.preload(workflows: :jobs)
        |> Map.fetch!(:workflows)
        |> List.first()
        |> Map.fetch!(:jobs)
        |> Enum.find(&(&1.name == "J1"))

      sandbox_job
      |> Ecto.Changeset.change(%{body: "fn(s => ({ ...s }));"})
      |> Repo.update!()

      assert {:ok, _updated_parent} = Sandboxes.merge(sandbox, parent, user)

      reloaded_parent_wf = Workflows.get_workflow(parent_wf.id)
      reloaded_job = Repo.reload!(parent_job)

      assert_eventually(
        Yex.Map.fetch!(workflow_map, "lock_version") ==
          reloaded_parent_wf.lock_version
      )

      assert reloaded_parent_wf.lock_version > initial_lock_version
      assert reloaded_job.body != "fn(s => s);"

      jobs_array = Yex.Doc.get_array(shared_doc, "jobs")

      job =
        Enum.find(jobs_array, fn job ->
          Yex.Map.fetch!(job, "id") == parent_job.id
        end)

      assert job |> Yex.Map.fetch!("body") |> Yex.Text.to_string() ==
               reloaded_job.body
    end
  end
end
