defmodule Lightning.WorkflowsTest do
  use Lightning.DataCase, async: true

  alias Lightning.{
    Workflows,
    Jobs,
    WorkflowsFixtures,
    JobsFixtures,
    ProjectsFixtures
  }

  describe "workflows" do
    test "list_workflows/0 returns all workflows" do
      workflow = WorkflowsFixtures.workflow_fixture()
      assert Workflows.list_workflows() == [workflow]
    end

    test "get_workflow!/1 returns the workflow with given id" do
      workflow = WorkflowsFixtures.workflow_fixture()
      assert Workflows.get_workflow!(workflow.id) == workflow

      assert_raise Ecto.NoResultsError, fn ->
        Workflows.get_workflow!(Ecto.UUID.generate())
      end
    end

    test "get_workflow/1 returns the workflow with given id" do
      assert Workflows.get_workflow(Ecto.UUID.generate()) == nil

      workflow = WorkflowsFixtures.workflow_fixture()
      assert Workflows.get_workflow(workflow.id) == workflow
    end

    test "create_workflow/1 with valid data creates a workflow" do
      project = ProjectsFixtures.project_fixture()
      valid_attrs = %{name: "some-name", project_id: project.id}

      assert {:ok, workflow} = Workflows.create_workflow(valid_attrs)

      assert {:error, %Ecto.Changeset{} = changeset} =
               Workflows.create_workflow(valid_attrs)

      assert %{
               name: [
                 "A workflow with this name does already exist in this project."
               ]
             } = errors_on(changeset)

      assert workflow.name == "some-name"
    end

    test "update_workflow/2 with valid data updates the workflow" do
      workflow = WorkflowsFixtures.workflow_fixture()
      update_attrs = %{name: "some-updated-name"}

      assert {:ok, workflow} = Workflows.update_workflow(workflow, update_attrs)

      assert workflow.name == "some-updated-name"
    end

    test "delete_workflow/1 deletes the workflow" do
      workflow = WorkflowsFixtures.workflow_fixture()

      job_1 = JobsFixtures.job_fixture(workflow_id: workflow.id)
      job_2 = JobsFixtures.job_fixture(workflow_id: workflow.id)

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
      workflow = WorkflowsFixtures.workflow_fixture()
      assert %Ecto.Changeset{} = Workflows.change_workflow(workflow)
    end
  end

  describe "workflows and edges" do
    test "using create_workflow/1" do
      project = ProjectsFixtures.project_fixture()
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
        edges: [%{source_trigger_id: trigger_id, target_job_id: job_id}]
      }

      assert {:ok, workflow} = Lightning.Workflows.create_workflow(valid_attrs)

      edge = workflow.edges |> List.first()
      assert edge.source_trigger_id == trigger_id
      assert edge.target_job_id == job_id

      assert workflow.name == "some-other-name"
    end

    test "using update_workflow/2" do
      project = ProjectsFixtures.project_fixture()

      job_id = Ecto.UUID.generate()
      trigger_id = Ecto.UUID.generate()

      valid_attrs = %{
        name: "some-name",
        project_id: project.id,
        jobs: [%{id: job_id, name: "some-job", body: "fn(state)"}],
        triggers: [%{id: trigger_id, type: :webhook}],
        edges: [%{source_trigger_id: trigger_id, target_job_id: job_id}]
      }

      {:ok, workflow} = Lightning.Workflows.create_workflow(valid_attrs)

      edge = workflow.edges |> List.first()

      # Updating a job and resubmitting the same edge should not create a new edge
      valid_attrs = %{
        jobs: [%{id: job_id, name: "some-job-renamed"}],
        edges: [
          %{id: edge.id, source_trigger_id: trigger_id, target_job_id: job_id}
        ]
      }

      assert {:ok, workflow} =
               Lightning.Workflows.update_workflow(workflow, valid_attrs)

      assert Repo.get_by(Lightning.Jobs.Job, id: job_id, name: "some-job-renamed")

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
      project = ProjectsFixtures.project_fixture()
      w1 = WorkflowsFixtures.workflow_fixture(project_id: project.id)
      w2 = WorkflowsFixtures.workflow_fixture(project_id: project.id)

      w1_job =
        JobsFixtures.job_fixture(
          name: "webhook job",
          project_id: project.id,
          workflow_id: w1.id,
          trigger: %{type: :webhook}
        )

      JobsFixtures.job_fixture(
        name: "on fail",
        project_id: project.id,
        workflow_id: w1.id,
        trigger: %{type: :on_job_failure, upstream_job_id: w1_job.id}
      )

      JobsFixtures.job_fixture(
        name: "on success",
        project_id: project.id,
        workflow_id: w1.id,
        trigger: %{type: :on_job_success, upstream_job_id: w1_job.id}
      )

      w2_job =
        JobsFixtures.job_fixture(
          name: "other workflow",
          project_id: project.id,
          workflow_id: w2.id,
          trigger: %{type: :webhook}
        )

      JobsFixtures.job_fixture(
        name: "on fail",
        project_id: project.id,
        workflow_id: w2.id,
        trigger: %{type: :on_job_failure, upstream_job_id: w2_job.id}
      )

      JobsFixtures.job_fixture(
        name: "unrelated job",
        trigger: %{type: :webhook}
      )

      %{project: project, w1: w1, w2: w2}
    end

    test "get_workflows_for/1", %{project: project, w1: w1, w2: w2} do
      results = Workflows.get_workflows_for(project)

      assert length(results) == 2

      assert w1.deleted_at == nil

      assert w2.deleted_at == nil

      assert (w1
              |> Repo.preload(
                jobs: [:credential, :workflow, trigger: [:upstream_job]]
              )) in results

      assert (w2
              |> Repo.preload(
                jobs: [:credential, :workflow, trigger: [:upstream_job]]
              )) in results

      assert length(results) == 2
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

      job_1 = JobsFixtures.job_fixture(workflow_id: w1.id)
      job_2 = JobsFixtures.job_fixture(workflow_id: w1.id)

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
