defmodule Lightning.WorkflowsTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.{
    Workflows,
    Jobs
  }

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

    test "create_workflow/1 with valid data creates a workflow" do
      project = insert(:project)
      valid_attrs = %{name: "some-name", project_id: project.id}

      assert {:ok, workflow} = Workflows.create_workflow(valid_attrs)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Workflows.create_workflow(valid_attrs)

      assert %{
               name: [
                 "A workflow with this name already exists in this project."
               ]
             } = errors_on(changeset)

      assert workflow.name == "some-name"
    end

    test "update_workflow/2 with valid data updates the workflow" do
      workflow = insert(:workflow)
      update_attrs = %{name: "some-updated-name"}

      assert {:ok, workflow} = Workflows.update_workflow(workflow, update_attrs)

      assert workflow.name == "some-updated-name"
    end

    test "delete_workflow/1 deletes the workflow" do
      workflow = insert(:workflow)

      job_1 = insert(:job, name: "job 1", workflow: workflow)
      job_2 = insert(:job, name: "job 2", workflow: workflow)

      assert {:ok, %Workflows.Workflow{}} = Workflows.delete_workflow(workflow)

      assert_raise Ecto.NoResultsError, fn ->
        Workflows.get_workflow!(workflow.id)
      end

      assert_raise Ecto.NoResultsError, fn ->
        Jobs.get_job!(job_1.id)
      end

      assert_raise Ecto.NoResultsError, fn ->
        Jobs.get_job!(job_2.id)
      end
    end

    test "change_workflow/1 returns a workflow changeset" do
      workflow = insert(:workflow)
      assert %Ecto.Changeset{} = Workflows.change_workflow(workflow)
    end
  end

  describe "workflows and edges" do
    test "get_edge_by_webhook/1 returns the job for a path" do
      workflow = insert(:workflow)
      job = insert(:job, workflow: workflow)
      trigger = insert(:trigger, workflow: workflow)

      edge =
        insert(:edge,
          workflow: workflow,
          source_trigger: trigger,
          target_job: job,
          condition: :always
        )

      assert Workflows.get_edge_by_webhook(trigger.id).id == edge.id

      Ecto.Changeset.change(trigger, custom_path: "foo")
      |> Lightning.Repo.update!()

      assert Workflows.get_edge_by_webhook(trigger.id) == nil

      assert Workflows.get_edge_by_webhook("foo").id == edge.id
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

      # Disabled Job
      insert(:job, %{
        enabled: false,
        workflow: t2.workflow
      })

      [e | _] = Workflows.get_edges_for_cron_execution(DateTime.utc_now())

      assert e.id == e2.id
    end

    test "using create_workflow/1" do
      project = insert(:project)
      valid_attrs = %{name: "some-name", project_id: project.id}

      assert {:ok, workflow} = Lightning.Workflows.create_workflow(valid_attrs)

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
            condition: :always,
            target_job_id: job_id
          }
        ]
      }

      assert {:ok, workflow} = Lightning.Workflows.create_workflow(valid_attrs)

      edge = workflow.edges |> List.first()
      assert edge.source_trigger_id == trigger_id
      assert edge.target_job_id == job_id

      assert workflow.name == "some-other-name"
    end

    test "using update_workflow/2" do
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
            condition: :always
          }
        ]
      }

      {:ok, workflow} = Lightning.Workflows.create_workflow(valid_attrs)

      edge = workflow.edges |> List.first()

      # Updating a job and resubmitting the same edge should not create a new edge
      valid_attrs = %{
        jobs: [%{id: job_id, name: "some-job-renamed"}],
        edges: [
          %{
            id: edge.id,
            source_trigger_id: trigger_id,
            target_job_id: job_id,
            condition: :always
          }
        ]
      }

      assert {:ok, workflow} =
               Lightning.Workflows.update_workflow(workflow, valid_attrs)

      assert Repo.get_by(Lightning.Jobs.Job,
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
               Lightning.Workflows.update_workflow(workflow, valid_attrs)

      assert workflow.name == "some-name"
      assert workflow.edges |> Enum.empty?()

      refute Repo.get(Lightning.Workflows.Edge, edge.id)
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
        condition: :on_job_failure,
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
        condition: :on_job_success,
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
        condition: :on_job_failure,
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
      results = Workflows.get_workflows_for(project)

      assert length(results) == 2

      assert w1.deleted_at == nil

      assert w2.deleted_at == nil

      job_1 = insert(:job, name: "job 1", workflow: w1)
      job_2 = insert(:job, name: "job 2", workflow: w1)

      # mark delete at request of a workflows and disable all associated jobs
      assert {:ok, _workflow} = Workflows.mark_for_deletion(w1)

      assert Workflows.get_workflow!(w1.id).deleted_at != nil

      assert Workflows.get_workflow!(w2.id).deleted_at == nil

      assert length(Workflows.get_workflows_for(project)) == 1

      assert Jobs.get_job!(job_1.id).enabled == false

      assert Jobs.get_job!(job_2.id).enabled == false
    end
  end
end
