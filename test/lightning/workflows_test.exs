defmodule Lightning.WorkflowsTest do
  use Lightning.DataCase, async: false

  import Lightning.Factories

  alias Lightning.Workflows
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
      project = insert(:project)
      valid_attrs = %{name: "some-name", project_id: project.id}

      assert {:ok, workflow} = Workflows.save_workflow(valid_attrs)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Workflows.save_workflow(valid_attrs)

      assert %{
               name: [
                 "a workflow with this name already exists in this project."
               ]
             } = errors_on(changeset)

      assert workflow.name == "some-name"
    end

    test "save_workflow/1 with valid data updates the workflow" do
      workflow = insert(:workflow)
      update_attrs = %{name: "some-updated-name"}

      assert {:ok, workflow} =
               Workflows.change_workflow(workflow, update_attrs)
               |> Workflows.save_workflow()

      assert workflow.name == "some-updated-name"
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
        {kafka_trigger_2, %{enabled: true}},
      ]

      changeset = workflow |> build_changeset(triggers)

      Events.subscribe_to_kafka_trigger_updated()

      changeset |> Workflows.save_workflow()

      assert_received %KafkaTriggerUpdated{trigger: ^kafka_trigger_1}
      assert_received %KafkaTriggerUpdated{trigger: ^kafka_trigger_2}
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
        {kafka_trigger_2, %{enabled: true}},
      ]

      changeset = workflow |> build_changeset(triggers)

      Events.subscribe_to_kafka_trigger_updated()

      changeset |> Workflows.save_workflow()

      refute_received %KafkaTriggerUpdated{trigger: ^kafka_trigger_1}
      refute_received %KafkaTriggerUpdated{trigger: ^kafka_trigger_2}
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

      assert {:ok, workflow} = Lightning.Workflows.save_workflow(valid_attrs)

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

      assert {:ok, workflow} = Lightning.Workflows.save_workflow(valid_attrs)

      edge = workflow.edges |> List.first()
      assert edge.source_trigger_id == trigger_id
      assert edge.target_job_id == job_id

      assert workflow.name == "some-other-name"
    end

    test "using save_workflow/2" do
      project = insert(:project)

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

      {:ok, workflow} = Workflows.save_workflow(valid_attrs)

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
               |> Workflows.save_workflow()

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
               |> Workflows.save_workflow()

      assert workflow.name == "some-name"
      assert workflow.edges |> Enum.empty?()

      refute Repo.get(Workflows.Edge, edge.id)
    end

    test "saving with locks" do
      valid_attrs = params_with_assocs(:workflow, jobs: [params_for(:job)])

      assert {:ok, workflow} = Workflows.save_workflow(valid_attrs)

      assert workflow.lock_version == 1

      assert {:ok, workflow} =
               Workflows.change_workflow(workflow, %{})
               |> Workflows.save_workflow()

      assert workflow.lock_version == 1,
             "lock_version should not change when no changes are made"

      assert {:ok, updated_workflow} =
               Workflows.change_workflow(workflow, %{jobs: [params_for(:job)]})
               |> Workflows.save_workflow()

      assert updated_workflow.lock_version == 2

      # Throws an error because the lock_version is outdated
      assert_raise Ecto.StaleEntryError, fn ->
        Workflows.change_workflow(workflow, %{jobs: [params_for(:job)]})
        |> Workflows.save_workflow()
      end
    end

    test "change_workflow/1 returns a workflow changeset" do
      workflow = insert(:workflow)
      assert %Ecto.Changeset{} = Workflows.change_workflow(workflow)
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

  describe "get_trigger_by_webhook/1" do
    test "returns a trigger when a matching custom_path is provided" do
      trigger = insert(:trigger, custom_path: "some_path")

      assert trigger |> unload_relation(:workflow) ==
               Workflows.get_trigger_by_webhook("some_path")
    end

    test "returns a trigger when a matching id is provided" do
      trigger = insert(:trigger)

      assert trigger |> unload_relation(:workflow) ==
               Workflows.get_trigger_by_webhook(trigger.id)
    end

    test "returns nil when no matching trigger is found" do
      insert(:trigger, custom_path: "some_path")
      assert Workflows.get_trigger_by_webhook("non_existent_path") == nil
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

  describe "create_edge/1" do
    test "creates a new edge, and captures a snapshot" do
      workflow = insert(:workflow)

      {:ok, edge} =
        params_for(:edge, workflow: workflow)
        |> Workflows.create_edge()

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

    test "mark_for_deletion/2", %{project: project, w1: w1, w2: w2} do
      workflows = Workflows.get_workflows_for(project)

      assert length(workflows) == 2

      assert w1.deleted_at == nil
      assert w2.deleted_at == nil

      %{id: trigger_1_id} = insert(:trigger, workflow: w1, enabled: true)
      %{id: trigger_2_id} = insert(:trigger, workflow: w1, enabled: true)

      # request workflow deletion (and disable all associated triggers)
      assert {:ok, _workflow} = Workflows.mark_for_deletion(w1)

      assert Workflows.get_workflow!(w1.id).deleted_at != nil
      assert Workflows.get_workflow!(w2.id).deleted_at == nil

      # check that get_workflows_for/1 doesn't return those marked for deletion
      assert length(Workflows.get_workflows_for(project)) == 1

      assert Repo.get(Trigger, trigger_1_id) |> Map.get(:enabled) == false
      assert Repo.get(Trigger, trigger_2_id) |> Map.get(:enabled) == false
    end
  end
end
