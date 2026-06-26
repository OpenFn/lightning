defmodule Lightning.Collaboration.WorkflowResolverTest do
  use Lightning.DataCase, async: true

  alias Lightning.Collaboration.WorkflowResolver
  alias Lightning.Workflows.Workflow

  import Lightning.Factories

  describe "resolve/3 with action: :new" do
    test "returns a freshly built struct when no row exists" do
      workflow_id = Ecto.UUID.generate()
      project = insert(:project)

      assert {:ok, %Workflow{} = workflow, :new} =
               WorkflowResolver.resolve(workflow_id, :new, project: project)

      # First-INSERT case: :built state routes to INSERT, lock_version is the
      # schema default 0.
      assert workflow.__meta__.state == :built
      assert workflow.id == workflow_id
      assert workflow.project_id == project.id
      assert workflow.lock_version == 0
      assert workflow.jobs == []
      assert workflow.edges == []
      assert workflow.triggers == []
    end

    test "works without a :project opt" do
      workflow_id = Ecto.UUID.generate()

      assert {:ok, %Workflow{} = workflow, :new} =
               WorkflowResolver.resolve(workflow_id, :new)

      assert workflow.__meta__.state == :built
      assert workflow.id == workflow_id
      assert workflow.project_id == nil
      assert workflow.lock_version == 0
    end

    test "resolves an existing row to :loaded (the #4830 reconcile-by-id guarantee)" do
      project = insert(:project)

      # Build a genuinely-new workflow, then persist it (build-then-save).
      workflow_id = Ecto.UUID.generate()

      {:ok, built, :new} =
        WorkflowResolver.resolve(workflow_id, :new, project: project)

      assert built.__meta__.state == :built

      user = insert(:user)

      {:ok, _persisted} =
        built
        |> Workflow.changeset(%{name: "Persisted Workflow"})
        |> Lightning.Workflows.save_workflow(user)

      # A "new" rejoin for an id that now has a row must resolve to the loaded
      # row so the next save routes to UPDATE, not a duplicate INSERT.
      assert {:ok, %Workflow{} = workflow, :existing} =
               WorkflowResolver.resolve(workflow_id, :new, project: project)

      assert workflow.__meta__.state == :loaded
      assert workflow.id == workflow_id
      assert workflow.lock_version == 1
    end
  end

  describe "resolve/3 with action: :edit" do
    test "returns {:error, :workflow_not_found} when no row exists" do
      assert {:error, :workflow_not_found} =
               WorkflowResolver.resolve(Ecto.UUID.generate(), :edit)
    end

    test "loads jobs/edges/triggers and sets has_auth_method per trigger" do
      project = insert(:project)
      user = insert(:user)
      workflow = insert(:workflow, project: project)

      insert(:job, workflow: workflow, name: "A Job")

      trigger_with_auth =
        insert(:trigger, type: :webhook, workflow: workflow)

      trigger_without_auth =
        insert(:trigger, type: :cron, workflow: workflow)

      auth_method =
        insert(:webhook_auth_method,
          project: project,
          name: "Basic Auth",
          auth_type: :basic
        )

      {:ok, _} =
        Lightning.WebhookAuthMethods.update_trigger_auth_methods(
          trigger_with_auth,
          [auth_method],
          actor: user
        )

      assert {:ok, %Workflow{} = resolved, :existing} =
               WorkflowResolver.resolve(workflow.id, :edit, project: project)

      assert resolved.__meta__.state == :loaded
      assert [%{name: "A Job"}] = resolved.jobs

      flags =
        Map.new(resolved.triggers, fn trigger ->
          {trigger.id, trigger.has_auth_method}
        end)

      assert flags[trigger_with_auth.id] == true
      assert flags[trigger_without_auth.id] == false
    end
  end

  describe "resolve/3 project ownership" do
    test "returns {:error, :wrong_project} when the row belongs elsewhere" do
      other_project = insert(:project)
      requesting_project = insert(:project)
      workflow = insert(:workflow, project: other_project)

      assert {:error, :wrong_project} =
               WorkflowResolver.resolve(workflow.id, :edit,
                 project: requesting_project
               )
    end

    test "does not enforce ownership when no :project opt is supplied" do
      workflow = insert(:workflow)

      assert {:ok, %Workflow{}, :existing} =
               WorkflowResolver.resolve(workflow.id, :edit)
    end
  end

  describe "resolve_version/3" do
    setup do
      project = insert(:project)
      user = insert(:user)

      workflow =
        insert(:workflow, project: project, name: "Versioned Workflow")

      job = insert(:job, workflow: workflow, name: "A Job")
      _edge = insert(:edge, workflow: workflow, target_job: job)

      trigger_with_auth =
        insert(:trigger, type: :webhook, workflow: workflow)

      trigger_without_auth =
        insert(:trigger, type: :cron, workflow: workflow)

      auth_method =
        insert(:webhook_auth_method,
          project: project,
          name: "Basic Auth",
          auth_type: :basic
        )

      {:ok, _} =
        Lightning.WebhookAuthMethods.update_trigger_auth_methods(
          trigger_with_auth,
          [auth_method],
          actor: user
        )

      # Snapshot the workflow at its current lock_version.
      reloaded =
        workflow.id
        |> Lightning.Workflows.get_workflow(include: [:jobs, :edges, :triggers])

      {:ok, snapshot} = Lightning.Workflows.Snapshot.create(reloaded)

      %{
        project: project,
        workflow: reloaded,
        snapshot: snapshot,
        trigger_with_auth: trigger_with_auth,
        trigger_without_auth: trigger_without_auth
      }
    end

    test "returns {:error, :snapshot_not_found} when no snapshot exists" do
      assert {:error, :snapshot_not_found} =
               WorkflowResolver.resolve_version(Ecto.UUID.generate(), 0)
    end

    test "hydrates a built struct matching the pre-refactor channel assembly",
         %{
           project: project,
           workflow: workflow,
           snapshot: snapshot,
           trigger_with_auth: trigger_with_auth,
           trigger_without_auth: trigger_without_auth
         } do
      assert {:ok, %Workflow{} = resolved, :version} =
               WorkflowResolver.resolve_version(
                 workflow.id,
                 snapshot.lock_version,
                 project: project
               )

      # Read-only point-in-time view: :built state carrying the snapshot's real
      # lock_version, tagged with kind :version so callers never confuse it with
      # a genuinely-new workflow.
      assert resolved.__meta__.state == :built
      assert resolved.lock_version == snapshot.lock_version
      assert resolved.id == workflow.id
      assert resolved.project_id == project.id
      assert resolved.name == snapshot.name
      assert resolved.deleted_at == nil

      # jobs/edges hydrated from the snapshot, one each.
      assert [%{name: "A Job"}] = resolved.jobs
      assert [%{}] = resolved.edges

      # per-trigger has_auth_method derived from the raw join query.
      flags =
        Map.new(resolved.triggers, fn trigger ->
          {trigger.id, trigger.has_auth_method}
        end)

      assert flags[trigger_with_auth.id] == true
      assert flags[trigger_without_auth.id] == false
    end

    test "dispatches from resolve/3 when a non-nil :version opt is present", %{
      project: project,
      workflow: workflow,
      snapshot: snapshot
    } do
      assert {:ok, %Workflow{lock_version: lock_version} = resolved, :version} =
               WorkflowResolver.resolve(workflow.id, :edit,
                 version: snapshot.lock_version,
                 project: project
               )

      assert lock_version == snapshot.lock_version
      assert resolved.__meta__.state == :built
    end

    test "sets project_id from the project without an ownership check", %{
      workflow: workflow,
      snapshot: snapshot
    } do
      # The version path sets project_id from the supplied project and performs
      # no ownership check, unlike the :edit latest path: a foreign project
      # still resolves.
      other_project = insert(:project)

      assert {:ok, %Workflow{project_id: project_id}, :version} =
               WorkflowResolver.resolve_version(
                 workflow.id,
                 snapshot.lock_version,
                 project: other_project
               )

      assert project_id == other_project.id
    end
  end

  describe "resolve/3 with an unknown action" do
    test "returns {:error, :invalid_action}" do
      assert {:error, :invalid_action} =
               WorkflowResolver.resolve(Ecto.UUID.generate(), :delete)
    end
  end
end
