defmodule Lightning.WorkflowsTest do
  use Lightning.DataCase, async: false

  import ExUnit.CaptureLog
  import Lightning.Factories

  alias Lightning.Auditing.Audit
  alias Lightning.Workflows
  alias Lightning.Workflows.Snapshot
  alias Lightning.Workflows.Trigger
  alias Lightning.Workflows.Triggers.Events
  alias Lightning.Workflows.Triggers.Events.KafkaTriggerUpdated

  describe "workflows" do
    test "list_workflows/0 returns all workflows" do
      workflow = insert(:workflow)

      assert Workflows.list_workflows() |> Enum.map(fn w -> w.id end) == [
               workflow.id
             ]
    end

    test "get_workflow!/1 returns the workflow with given id" do
      workflow = insert(:workflow)

      assert Workflows.get_workflow!(workflow.id) |> unload_relation(:project) ==
               workflow |> unload_relation(:project)

      assert_raise Ecto.NoResultsError, fn ->
        Workflows.get_workflow!(Ecto.UUID.generate())
      end
    end

    test "get_workflow/1 returns the workflow with given id" do
      assert Workflows.get_workflow(Ecto.UUID.generate()) == nil

      workflow = insert(:workflow)

      assert Workflows.get_workflow(workflow.id) |> unload_relation(:project) ==
               workflow |> unload_relation(:project)
    end

    test "save_workflow/1 with valid data creates a workflow" do
      user = insert(:user)
      project = insert(:project)
      valid_attrs = %{name: "some-name", project_id: project.id}

      assert {:ok, workflow} = Workflows.save_workflow(valid_attrs, user)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Workflows.save_workflow(valid_attrs, user)

      assert %{
               name: [
                 "A workflow with this name already exists (possibly pending deletion) in this project."
               ]
             } = errors_on(changeset)

      assert workflow.name == "some-name"
    end

    test "save_workflow/1 with valid data updates the workflow" do
      workflow = insert(:workflow)
      update_attrs = %{name: "some-updated-name"}

      assert {:ok, workflow} =
               Workflows.change_workflow(workflow, update_attrs)
               |> Workflows.save_workflow(insert(:user))

      assert workflow.name == "some-updated-name"
    end

    test "save_workflow/1 for a deleted workflow returns an error" do
      user = insert(:user)
      workflow = insert(:workflow, deleted_at: DateTime.utc_now())
      update_attrs = %{name: "some-updated-name"}

      assert {:error, :workflow_deleted} =
               Workflows.change_workflow(workflow, update_attrs)
               |> Workflows.save_workflow(user)
    end

    test "save_workflow/1 with changeset audits creation of the snapshot" do
      %{id: user_id} = user = insert(:user)
      %{id: workflow_id} = workflow = insert(:workflow)
      update_attrs = %{name: "some-updated-name"}

      workflow
      |> Workflows.change_workflow(update_attrs)
      |> Workflows.save_workflow(user)

      %{id: snapshot_id} = Snapshot |> Repo.one!()

      assert %{
               event: "snapshot_created",
               item_type: "workflow",
               item_id: ^workflow_id,
               actor_id: ^user_id,
               changes: %{
                 after: %{
                   "snapshot_id" => ^snapshot_id
                 }
               }
             } = Repo.one(Audit)
    end

    test "save_workflow/1 with attrs audits creation of the snapshot" do
      %{id: user_id} = user = insert(:user)
      project = insert(:project)
      valid_attrs = %{name: "some-name", project_id: project.id}

      {:ok, %{id: workflow_id}} = Workflows.save_workflow(valid_attrs, user)

      %{id: snapshot_id} = Snapshot |> Repo.one!()

      assert %{
               event: "snapshot_created",
               item_type: "workflow",
               item_id: ^workflow_id,
               actor_id: ^user_id,
               changes: %{
                 after: %{
                   "snapshot_id" => ^snapshot_id
                 }
               }
             } = Repo.one(Audit)
    end

    test "save_workflow/1 records a version" do
      user = insert(:user)
      project = insert(:project)

      # Create a new workflow
      valid_attrs = %{name: "versioned-workflow", project_id: project.id}
      {:ok, workflow} = Workflows.save_workflow(valid_attrs, user)

      # Reload to get updated version_history
      workflow = Repo.reload!(workflow)

      # Check that a version was recorded
      assert length(workflow.version_history) == 1

      # Verify the version exists in the database
      version =
        Lightning.Workflows.WorkflowVersion
        |> Repo.get_by!(workflow_id: workflow.id)

      assert "#{version.source}:#{version.hash}" == hd(workflow.version_history)
      assert version.source == "app"
    end

    test "save_workflow/1 audits when a trigger is enabled" do
      %{id: user_id} = user = insert(:user)
      workflow = create_workflow()

      {:ok, _workflow} =
        workflow
        |> Workflows.update_triggers_enabled_state(true)
        |> Workflows.save_workflow(user)

      assert_trigger_state_audit(workflow.id, user_id, false, true, "enabled")
    end

    test "save_workflow/1 audits when a trigger is disabled" do
      %{id: user_id} = user = insert(:user)
      workflow = create_workflow(enabled: true)

      {:ok, _workflow} =
        workflow
        |> Workflows.update_triggers_enabled_state(false)
        |> Workflows.save_workflow(user)

      assert_trigger_state_audit(workflow.id, user_id, true, false, "disabled")
    end

    test "save_workflow/1 does not audit when trigger enabled state doesn't change" do
      user = insert(:user)
      workflow = create_workflow(enabled: true)

      {:ok, _workflow} =
        workflow
        |> Workflows.update_triggers_enabled_state(true)
        |> Workflows.save_workflow(user)

      assert Repo.aggregate(Audit, :count) == 0
    end

    test "save_workflow/1 does not audit when updating other workflow attributes" do
      user = insert(:user)
      workflow = create_workflow(enabled: true)

      {:ok, _workflow} =
        workflow
        |> Workflows.change_workflow(%{name: "updated name"})
        |> Workflows.save_workflow(user)

      assert Repo.aggregate(
               from(a in Audit, where: a.event in ["enabled", "disabled"]),
               :count
             ) == 0
    end

    test "save_workflow/1 with simultaneous trigger and name changes only audits trigger" do
      %{id: user_id} = user = insert(:user)
      workflow = create_workflow(enabled: true)

      {:ok, _workflow} =
        workflow
        |> Workflows.change_workflow(%{name: "new name"})
        |> Workflows.update_triggers_enabled_state(false)
        |> Workflows.save_workflow(user)

      assert_trigger_state_audit(workflow.id, user_id, true, false, "disabled")

      assert Repo.aggregate(
               from(a in Audit, where: a.event in ["enabled", "disabled"]),
               :count
             ) == 1
    end

    test "save_workflow/1 publishes event for updated Kafka triggers" do
      kafka_configuration = build(:triggers_kafka_configuration)

      workflow = insert(:workflow) |> Repo.preload(:triggers)

      kafka_trigger_1 =
        insert(
          :trigger,
          type: :kafka,
          workflow: workflow,
          kafka_configuration: kafka_configuration,
          enabled: false
        )

      cron_trigger_1 =
        insert(
          :trigger,
          type: :cron,
          workflow: workflow,
          enabled: false
        )

      kafka_trigger_2 =
        insert(
          :trigger,
          type: :kafka,
          workflow: workflow,
          kafka_configuration: kafka_configuration,
          enabled: false
        )

      triggers = [
        {kafka_trigger_1, %{enabled: true}},
        {cron_trigger_1, %{enabled: true}},
        {kafka_trigger_2, %{enabled: true}}
      ]

      kafka_trigger_1_id = kafka_trigger_1.id
      cron_trigger_1_id = cron_trigger_1.id
      kafka_trigger_2_id = kafka_trigger_2.id

      changeset = workflow |> build_changeset(triggers)

      Events.subscribe_to_kafka_trigger_updated()

      changeset |> Workflows.save_workflow(insert(:user))

      assert_received %KafkaTriggerUpdated{trigger_id: ^kafka_trigger_1_id}
      assert_received %KafkaTriggerUpdated{trigger_id: ^kafka_trigger_2_id}
      refute_received %KafkaTriggerUpdated{trigger_id: ^cron_trigger_1_id}
    end

    test "save_workflow/1 does not publish events if save fails" do
      kafka_configuration = build(:triggers_kafka_configuration)

      workflow = insert(:workflow) |> Repo.preload(:triggers)

      kafka_trigger_1 =
        insert(
          :trigger,
          type: :kafka,
          workflow: workflow,
          kafka_configuration: kafka_configuration,
          enabled: false
        )

      cron_trigger_1 =
        insert(
          :trigger,
          type: :cron,
          workflow: workflow,
          enabled: false
        )

      kafka_trigger_2 =
        insert(
          :trigger,
          type: :kafka,
          workflow: workflow,
          kafka_configuration: kafka_configuration,
          enabled: false
        )

      triggers = [
        {kafka_trigger_1, %{enabled: true}},
        {cron_trigger_1, %{type: :unobtainium}},
        {kafka_trigger_2, %{enabled: true}}
      ]

      kafka_trigger_1_id = kafka_trigger_1.id
      cron_trigger_1_id = cron_trigger_1.id
      kafka_trigger_2_id = kafka_trigger_2.id

      changeset = workflow |> build_changeset(triggers)

      Events.subscribe_to_kafka_trigger_updated()

      changeset |> Workflows.save_workflow(nil)

      refute_received %KafkaTriggerUpdated{trigger_id: ^kafka_trigger_1_id}
      refute_received %KafkaTriggerUpdated{trigger_id: ^kafka_trigger_2_id}
      refute_received %KafkaTriggerUpdated{trigger_id: ^cron_trigger_1_id}
    end

    defp build_changeset(workflow, triggers_and_attrs) do
      triggers_changes =
        triggers_and_attrs
        |> Enum.map(fn {trigger, attrs} ->
          Trigger.changeset(trigger, attrs)
        end)

      Ecto.Changeset.change(workflow, triggers: triggers_changes)
    end

    test "save_workflow/1 using attrs" do
      project = insert(:project)
      valid_attrs = %{name: "some-name", project_id: project.id}
      user = insert(:user)

      assert {:ok, workflow} =
               Lightning.Workflows.save_workflow(valid_attrs, user)

      assert workflow.name == "some-name"

      job_id = Ecto.UUID.generate()
      trigger_id = Ecto.UUID.generate()

      valid_attrs = %{
        name: "some-other-name",
        project_id: project.id,
        jobs: [%{id: job_id, name: "some-job", body: "fn(state)"}],
        triggers: [%{id: trigger_id, type: :webhook}],
        edges: [
          %{
            source_trigger_id: trigger_id,
            condition_type: :always,
            target_job_id: job_id
          }
        ]
      }

      assert {:ok, workflow} =
               Lightning.Workflows.save_workflow(valid_attrs, user)

      edge = workflow.edges |> List.first()
      assert edge.source_trigger_id == trigger_id
      assert edge.target_job_id == job_id

      assert workflow.name == "some-other-name"
    end

    test "using save_workflow/2" do
      project = insert(:project)
      user = insert(:user)

      job_id = Ecto.UUID.generate()
      trigger_id = Ecto.UUID.generate()

      valid_attrs = %{
        name: "some-name",
        project_id: project.id,
        jobs: [%{id: job_id, name: "some-job", body: "fn(state)"}],
        triggers: [%{id: trigger_id, type: :webhook}],
        edges: [
          %{
            source_trigger_id: trigger_id,
            target_job_id: job_id,
            condition_type: :always
          }
        ]
      }

      {:ok, workflow} = Workflows.save_workflow(valid_attrs, user)

      edge = workflow.edges |> List.first()

      # Updating a job and resubmitting the same edge should not create a new edge
      valid_attrs = %{
        jobs: [%{id: job_id, name: "some-job-renamed"}],
        edges: [
          %{
            id: edge.id,
            source_trigger_id: trigger_id,
            target_job_id: job_id,
            condition_type: :always
          }
        ]
      }

      assert {:ok, workflow} =
               Workflows.change_workflow(workflow, valid_attrs)
               |> Workflows.save_workflow(user)

      assert Repo.get_by(Workflows.Job,
               id: job_id,
               name: "some-job-renamed"
             )

      assert workflow.name == "some-name"
      assert workflow.edges |> List.first() == edge

      valid_attrs = %{
        jobs: [%{id: job_id, name: "some-job"}],
        triggers: [%{id: trigger_id, type: :webhook}],
        edges: []
      }

      assert {:ok, workflow} =
               Workflows.change_workflow(workflow, valid_attrs)
               |> Workflows.save_workflow(user)

      assert workflow.name == "some-name"
      assert workflow.edges |> Enum.empty?()

      refute Repo.get(Workflows.Edge, edge.id)
    end

    test "saving with locks" do
      user = insert(:user)
      valid_attrs = params_with_assocs(:workflow, jobs: [params_for(:job)])

      assert {:ok, workflow} =
               Workflows.save_workflow(valid_attrs, insert(:user))

      assert workflow.lock_version == 1

      assert {:ok, workflow} =
               Workflows.change_workflow(workflow, %{})
               |> Workflows.save_workflow(user)

      assert workflow.lock_version == 1,
             "lock_version should not change when no changes are made"

      assert {:ok, updated_workflow} =
               Workflows.change_workflow(workflow, %{jobs: [params_for(:job)]})
               |> Workflows.save_workflow(user)

      assert updated_workflow.lock_version == 2

      # Throws an error because the lock_version is outdated
      assert_raise Ecto.StaleEntryError, fn ->
        Workflows.change_workflow(workflow, %{jobs: [params_for(:job)]})
        |> Workflows.save_workflow(user)
      end
    end

    test "change_workflow/1 returns a workflow changeset" do
      workflow = insert(:workflow)
      assert %Ecto.Changeset{} = Workflows.change_workflow(workflow)
    end

    test "maybe_create_latest_snapshot/1 creates snapshot if missing latest" do
      workflow =
        insert(:simple_workflow, lock_version: 2, updated_at: DateTime.utc_now())

      refute Snapshot.get_current_for(workflow)

      assert capture_log(fn ->
               assert {:ok, %Snapshot{lock_version: 2}} =
                        Workflows.maybe_create_latest_snapshot(workflow)
             end) =~
               "Created latest snapshot for #{workflow.id} (last_update: #{workflow.updated_at})"
    end

    test "maybe_create_latest_snapshot/1 does not create snapshot if latest exists" do
      {:ok, workflow} =
        insert(:simple_workflow)
        |> Workflows.change_workflow(%{name: "some-updated-name"})
        |> Workflows.save_workflow(insert(:user))

      %{lock_version: lock_version} = Snapshot.get_current_for(workflow)

      assert {:ok, %Snapshot{lock_version: ^lock_version}} =
               Workflows.maybe_create_latest_snapshot(workflow)
    end
  end

  describe "finders" do
    test "get_webhook_trigger/1 returns the trigger for a path" do
      %{triggers: [trigger]} =
        insert(:simple_workflow) |> Repo.preload(:triggers)

      assert Workflows.get_webhook_trigger(trigger.id).id == trigger.id

      Ecto.Changeset.change(trigger, custom_path: "foo")
      |> Lightning.Repo.update!()

      assert Workflows.get_webhook_trigger(trigger.id) == nil

      assert Workflows.get_webhook_trigger("foo").id == trigger.id
    end

    test "get_webhook_trigger/1 does not return a trigger when type is cron" do
      %{triggers: [trigger]} =
        insert(:simple_workflow) |> Repo.preload(:triggers)

      # Change the trigger type to cron
      Ecto.Changeset.change(trigger, type: :cron)
      |> Lightning.Repo.update!()

      # Should not return the trigger even though the ID matches
      assert Workflows.get_webhook_trigger(trigger.id) == nil

      # Set a custom path and verify it still doesn't return
      Ecto.Changeset.change(trigger, custom_path: "cron_path")
      |> Lightning.Repo.update!()

      assert Workflows.get_webhook_trigger("cron_path") == nil
    end

    test "get_jobs_for_cron_execution/0 returns jobs to run for a given time" do
      t1 = insert(:trigger, %{type: :cron, cron_expression: "5 0 * 8 *"})
      job_0 = insert(:job, %{workflow: t1.workflow})

      insert(:edge, %{
        workflow: t1.workflow,
        source_trigger: t1,
        target_job: job_0
      })

      t2 = insert(:trigger, %{type: :cron, cron_expression: "* * * * *"})
      job_1 = insert(:job, %{workflow: t2.workflow})

      e2 =
        insert(:edge, %{
          workflow: t2.workflow,
          source_trigger: t2,
          target_job: job_1
        })

      insert(:job, %{
        workflow: t2.workflow
      })

      [e | _] = Workflows.get_edges_for_cron_execution(DateTime.utc_now())

      assert e.id == e2.id
    end
  end

  describe "get_webhook_trigger/1" do
    test "returns a trigger when a matching custom_path is provided" do
      trigger = insert(:trigger, custom_path: "some_path")

      assert trigger |> unload_relation(:workflow) ==
               Workflows.get_webhook_trigger("some_path")
    end

    test "returns a trigger when a matching id is provided" do
      trigger = insert(:trigger)

      assert trigger |> unload_relation(:workflow) ==
               Workflows.get_webhook_trigger(trigger.id)
    end

    test "returns nil when no matching trigger is found" do
      insert(:trigger, custom_path: "some_path")
      assert Workflows.get_webhook_trigger("non_existent_path") == nil
    end
  end

  describe "get_edge_by_trigger/1" do
    test "returns an edge when associated trigger is provided" do
      workflow = insert(:workflow)
      trigger = insert(:trigger, workflow: workflow)
      job = insert(:job, workflow: workflow)

      edge =
        insert(:edge,
          workflow: workflow,
          source_trigger_id: trigger.id,
          target_job_id: job.id
        )

      assert edge |> unload_relation(:workflow) ==
               Workflows.get_edge_by_trigger(trigger)
               |> unload_relations([:target_job, :source_trigger])
    end

    test "returns nil when no associated edge is found" do
      trigger = insert(:trigger)
      assert Workflows.get_edge_by_trigger(trigger) == nil
    end
  end

  describe "create_edge/2" do
    setup do
      %{user: insert(:user)}
    end

    test "creates a new edge, and captures a snapshot", %{user: user} do
      workflow = insert(:workflow)

      {:ok, edge} =
        params_for(:edge, workflow: workflow)
        |> Workflows.create_edge(user)

      updated_workflow = Ecto.assoc(edge, :workflow) |> Repo.one!()

      assert updated_workflow.lock_version > workflow.lock_version

      snapshot = Workflows.Snapshot.get_current_for(workflow)

      snapshotted_edge = snapshot.edges |> Enum.find(&(&1.id == edge.id))

      assert snapshotted_edge.id == edge.id
      assert snapshotted_edge.updated_at == edge.updated_at

      fields = [
        :id,
        :enabled,
        :inserted_at,
        :updated_at,
        :condition_type,
        :condition_label,
        :source_job_id,
        :source_trigger_id,
        :target_job_id
      ]

      [snapshotted_edge, edge]
      |> Enum.map(fn model ->
        Map.take(model, fields)
      end)
      |> then(fn [lhs, rhs] ->
        assert lhs == rhs
      end)
    end

    test "snapshot is audited with the appropriate user", %{
      user: %{id: user_id} = user
    } do
      workflow = insert(:workflow)

      assert {:ok, _} =
               :edge
               |> params_for(workflow: workflow)
               |> Workflows.create_edge(user)

      assert %{actor_id: ^user_id} = Audit |> Repo.one!()
    end
  end

  describe "workflows and project spaces" do
    setup do
      project = insert(:project)
      w1 = insert(:workflow, project: project)
      w2 = insert(:workflow, project: project)

      w1_job =
        insert(:job,
          name: "webhook job",
          project: project,
          workflow: w1
          # trigger: %{type: :webhook}
        )

      insert(:edge,
        workflow: w1,
        source_job: w1_job,
        condition_type: :on_job_failure,
        target_job:
          insert(:job,
            name: "on fail",
            project: project,
            workflow: w1
          )
      )

      insert(:edge,
        workflow: w1,
        source_job: w1_job,
        condition_type: :on_job_success,
        target_job:
          insert(:job,
            name: "on success",
            project: project,
            workflow: w1
          )
      )

      w2_job =
        insert(:job,
          name: "other workflow",
          project: project,
          workflow: w2
          # trigger: %{type: :webhook}
        )

      insert(:edge,
        workflow: w2,
        source_job: w2_job,
        condition_type: :on_job_failure,
        target_job:
          insert(:job,
            name: "on fail",
            project: project,
            workflow: w2
          )
      )

      insert(:job,
        name: "unrelated job"
        # trigger: %{type: :webhook}
      )

      %{project: project, w1: w1, w2: w2}
    end

    test "get_workflows_for/1", %{project: project, w1: w1, w2: w2} do
      results = Workflows.get_workflows_for(project)

      assert length(results) == 2

      assert results |> MapSet.new(& &1.id) == [w1, w2] |> MapSet.new(& &1.id)

      for workflow <- results do
        assert is_nil(workflow.deleted_at)
        assert workflow.jobs != %Ecto.Association.NotLoaded{}

        for job <- workflow.jobs do
          assert job.credential != %Ecto.Association.NotLoaded{}
          assert job.workflow != %Ecto.Association.NotLoaded{}
        end

        assert workflow.triggers != %Ecto.Association.NotLoaded{}
        assert workflow.edges != %Ecto.Association.NotLoaded{}
      end
    end

    test "to_project_spec/1", %{project: project, w1: w1, w2: w2} do
      workflows = Workflows.get_workflows_for(project)

      project_space = Workflows.to_project_space(workflows)

      assert %{"id" => w1.id, "name" => w1.name} in project_space["workflows"]
      assert %{"id" => w2.id, "name" => w2.name} in project_space["workflows"]

      w1_id = w1.id

      assert project_space["jobs"]
             |> Enum.filter(&match?(%{"workflowId" => ^w1_id}, &1))
             |> length() == 3

      w2_id = w2.id

      assert project_space["jobs"]
             |> Enum.filter(&match?(%{"workflowId" => ^w2_id}, &1))
             |> length() == 2
    end

    test "mark_for_deletion/3", %{project: project, w1: w1, w2: w2} do
      user = insert(:user)

      workflows = Workflows.get_workflows_for(project)

      assert length(workflows) == 2

      assert w1.deleted_at == nil
      assert w2.deleted_at == nil

      %{id: trigger_1_id} = insert(:trigger, workflow: w1, enabled: true)
      %{id: trigger_2_id} = insert(:trigger, workflow: w1, enabled: true)
      %{id: trigger_3_id} = insert(:trigger, workflow: w2, enabled: true)

      # request workflow deletion (and disable all associated triggers)
      assert {:ok, _workflow} = Workflows.mark_for_deletion(w1, user)

      assert Workflows.get_workflow!(w1.id).deleted_at != nil
      assert Workflows.get_workflow!(w2.id).deleted_at == nil

      # check that get_workflows_for/1 doesn't return those marked for deletion
      assert length(Workflows.get_workflows_for(project)) == 1

      assert Repo.get(Trigger, trigger_1_id) |> Map.get(:enabled) == false
      assert Repo.get(Trigger, trigger_2_id) |> Map.get(:enabled) == false
      assert Repo.get(Trigger, trigger_3_id) |> Map.get(:enabled) == true
    end

    test "mark_for_deletion/3 creates an audit event", %{
      w1: %{id: workflow_id} = workflow
    } do
      %{id: user_id} = user = insert(:user)

      assert {:ok, _workflow} = Workflows.mark_for_deletion(workflow, user)

      audit = Repo.one!(Audit)

      assert %{
               event: "marked_for_deletion",
               item_id: ^workflow_id,
               actor_id: ^user_id
             } = audit
    end

    test "mark_for_deletion/3 publishes events for Kafka triggers", %{w1: w1} do
      user = insert(:user)

      %{id: kafka_trigger_1_id} =
        insert(:trigger, workflow: w1, enabled: true, type: :kafka)

      %{id: webhook_trigger_id} =
        insert(:trigger, workflow: w1, enabled: true, type: :webhook)

      %{id: kafka_trigger_2_id} =
        insert(:trigger, workflow: w1, enabled: true, type: :kafka)

      Events.subscribe_to_kafka_trigger_updated()

      assert {:ok, _workflow} = Workflows.mark_for_deletion(w1, user)

      refute_received %KafkaTriggerUpdated{trigger_id: ^webhook_trigger_id}
      assert_received %KafkaTriggerUpdated{trigger_id: ^kafka_trigger_2_id}
      assert_received %KafkaTriggerUpdated{trigger_id: ^kafka_trigger_1_id}
    end

    test "mark_for_deletion/3 renames workflow with _del suffix" do
      # Use a separate project to avoid pollution from setup
      project = insert(:project)
      user = insert(:user)
      w1 = insert(:workflow, project: project, name: "Test Workflow")

      assert {:ok, %{workflow: workflow}} = Workflows.mark_for_deletion(w1, user)
      assert workflow.name == "Test Workflow_del01"

      # Test incrementing when deleting another workflow with the same name
      w2 = insert(:workflow, project: project, name: "Test Workflow")

      assert {:ok, %{workflow: workflow2}} =
               Workflows.mark_for_deletion(w2, user)

      assert workflow2.name == "Test Workflow_del02"

      # Test incrementing again
      w3 = insert(:workflow, project: project, name: "Test Workflow")

      assert {:ok, %{workflow: workflow3}} =
               Workflows.mark_for_deletion(w3, user)

      assert workflow3.name == "Test Workflow_del03"
    end

    test "allows reusing workflow name after marking for deletion, then validates error when using deleted workflow name" do
      project = insert(:project)
      user = insert(:user)
      w1 = insert(:workflow, project: project, name: "My Workflow")

      # Mark workflow for deletion
      assert {:ok, %{workflow: deleted_workflow}} =
               Workflows.mark_for_deletion(w1, user)

      assert deleted_workflow.name == "My Workflow_del01"

      # Should be able to create a new workflow with the original name
      assert {:ok, new_workflow} =
               Workflows.save_workflow(
                 %{name: "My Workflow", project_id: project.id},
                 user
               )

      assert new_workflow.name == "My Workflow"
      assert new_workflow.deleted_at == nil

      # Should NOT be able to create another workflow with the deleted workflow's name
      assert {:error, changeset} =
               Workflows.save_workflow(
                 %{name: "My Workflow_del01", project_id: project.id},
                 user
               )

      assert errors_on(changeset) == %{
               name: [
                 "a workflow with this name already exists (possibly pending deletion) in this project."
               ]
             }
    end
  end

  describe "get_workflows_for/2" do
    setup do
      project = insert(:project)

      w1 = insert(:workflow, project: project, name: "API Gateway")
      w2 = insert(:workflow, project: project, name: "Background Jobs")
      w3 = insert(:workflow, project: project, name: "REST API")

      insert(:trigger, workflow: w1, enabled: true)
      insert(:trigger, workflow: w2, enabled: false)
      insert(:trigger, workflow: w3, enabled: true)

      %{project: project, w1: w1, w2: w2, w3: w3}
    end

    test "returns all workflows for a project", %{project: project} do
      workflows = Workflows.get_workflows_for(project)
      assert length(workflows) == 3
    end

    test "filters workflows by search term", %{project: project} do
      workflows = Workflows.get_workflows_for(project, search: "api")
      assert length(workflows) == 2

      assert Enum.map(workflows, & &1.name) |> Enum.sort() == [
               "API Gateway",
               "REST API"
             ]
    end

    test "returns empty list for non-matching search", %{project: project} do
      workflows = Workflows.get_workflows_for(project, search: "nonexistent")
      assert workflows == []
    end

    test "sorts workflows by name ascending", %{project: project} do
      workflows = Workflows.get_workflows_for(project, order_by: {:name, :asc})
      names = Enum.map(workflows, & &1.name)
      assert names == ["API Gateway", "Background Jobs", "REST API"]
    end

    test "sorts workflows by name descending", %{project: project} do
      workflows = Workflows.get_workflows_for(project, order_by: {:name, :desc})
      names = Enum.map(workflows, & &1.name)
      assert names == ["REST API", "Background Jobs", "API Gateway"]
    end

    test "sorts workflows by enabled state ascending", %{project: project} do
      workflows =
        Workflows.get_workflows_for(project, order_by: {:enabled, :asc})

      first_workflow = List.first(workflows)
      last_workflow = List.last(workflows)

      assert first_workflow.triggers |> Enum.any?(& &1.enabled) == false
      assert last_workflow.triggers |> Enum.any?(& &1.enabled) == true
    end

    test "sorts workflows by enabled state descending", %{project: project} do
      workflows =
        Workflows.get_workflows_for(project, order_by: {:enabled, :desc})

      first_workflow = List.first(workflows)
      last_workflow = List.last(workflows)

      assert first_workflow.triggers |> Enum.any?(& &1.enabled) == true
      assert last_workflow.triggers |> Enum.any?(& &1.enabled) == false
    end

    test "uses default sorting for invalid order_by", %{project: project} do
      workflows =
        Workflows.get_workflows_for(project, order_by: {:invalid, :asc})

      names = Enum.map(workflows, & &1.name)
      assert names == ["API Gateway", "Background Jobs", "REST API"]
    end

    test "customizes preloaded associations", %{project: project} do
      workflows = Workflows.get_workflows_for(project, include: [:triggers])
      workflow = List.first(workflows)

      assert workflow.triggers != %Ecto.Association.NotLoaded{}
      assert match?(%Ecto.Association.NotLoaded{}, workflow.edges)
    end

    test "always includes triggers even if not specified", %{project: project} do
      workflows = Workflows.get_workflows_for(project, include: [:edges])
      workflow = List.first(workflows)

      assert workflow.triggers != %Ecto.Association.NotLoaded{}
      assert workflow.edges != %Ecto.Association.NotLoaded{}
    end

    test "ignores empty search term", %{project: project} do
      workflows = Workflows.get_workflows_for(project, search: "")
      assert length(workflows) == 3
    end
  end

  defp assert_trigger_state_audit(
         workflow_id,
         user_id,
         before_state,
         after_state,
         event
       ) do
    audit =
      from(a in Audit, where: a.event in ["enabled", "disabled"]) |> Repo.one!()

    assert %{
             event: ^event,
             item_type: "workflow",
             item_id: ^workflow_id,
             actor_id: ^user_id,
             changes: %{
               before: %{"enabled" => ^before_state},
               after: %{"enabled" => ^after_state}
             }
           } = audit
  end

  defp create_workflow(opts \\ []) do
    enabled = Keyword.get(opts, :enabled, false)
    trigger = build(:trigger, type: :cron, enabled: enabled)
    job = build(:job)

    build(:workflow)
    |> with_job(job)
    |> with_trigger(trigger)
    |> with_edge({trigger, job})
    |> insert()
  end
end
