defmodule Lightning.WorkflowsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Workflows
  alias Lightning.Workflows.Workflow

  import Lightning.WorkflowsFixtures

  describe "workflows" do
    test "list_workflows/0 returns all workflows" do
      workflow = workflow_fixture()
      assert Workflows.list_workflows() == [workflow]
    end

    test "get_workflow!/1 returns the workflow with given id" do
      workflow = workflow_fixture()
      assert Workflows.get_workflow!(workflow.id) == workflow

      assert_raise Ecto.NoResultsError, fn ->
        Workflows.get_workflow!(Ecto.UUID.generate())
      end
    end

    test "get_workflow/1 returns the workflow with given id" do
      assert Workflows.get_workflow(Ecto.UUID.generate()) == nil

      workflow = workflow_fixture()
      assert Workflows.get_workflow(workflow.id) == workflow
    end

    test "create_workflow/1 with valid data creates a workflow" do
      valid_attrs = %{name: "some-name"}

      assert {:ok, %Workflow{} = workflow} =
               Workflows.create_workflow(valid_attrs)

      assert workflow.name == "some-name"
    end

    test "update_workflow/2 with valid data updates the workflow" do
      workflow = workflow_fixture()
      update_attrs = %{name: "some-updated-name"}

      assert {:ok, %Workflow{} = workflow} =
               Workflows.update_workflow(workflow, update_attrs)

      assert workflow.name == "some-updated-name"
    end

    test "delete_workflow/1 deletes the workflow" do
      workflow = workflow_fixture()
      assert {:ok, %Workflow{}} = Workflows.delete_workflow(workflow)

      assert_raise Ecto.NoResultsError, fn ->
        Workflows.get_workflow!(workflow.id)
      end
    end

    test "change_workflow/1 returns a workflow changeset" do
      workflow = workflow_fixture()
      assert %Ecto.Changeset{} = Workflows.change_workflow(workflow)
    end
  end
end
