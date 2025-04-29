defmodule Lightning.WorkflowTemplatesTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.WorkflowTemplates
  alias Lightning.Workflows.WorkflowTemplate

  describe "create_template/1" do
    test "creates a new template when none exists for the workflow" do
      workflow = insert(:workflow)

      attrs = %{
        "name" => "My Template",
        "code" => "workflow code",
        "workflow_id" => workflow.id,
        "tags" => ["tag1", "tag2"]
      }

      assert {:ok, %WorkflowTemplate{} = template} =
               WorkflowTemplates.create_template(attrs)

      assert template.name == "My Template"
      assert template.code == "workflow code"
      assert template.workflow_id == workflow.id
      assert template.tags == ["tag1", "tag2"]
    end

    test "updates existing template when one exists for the workflow" do
      workflow = insert(:workflow)
      template = insert(:workflow_template, workflow: workflow, name: "Old Name")

      attrs = %{
        "name" => "New Name",
        "code" => "new code",
        "workflow_id" => workflow.id,
        "tags" => ["new", "tags"]
      }

      assert {:ok, %WorkflowTemplate{} = updated_template} =
               WorkflowTemplates.create_template(attrs)

      assert updated_template.id == template.id
      assert updated_template.name == "New Name"
      assert updated_template.code == "new code"
      assert updated_template.tags == ["new", "tags"]
    end

    test "returns error when required fields are missing" do
      attrs = %{
        "name" => "My Template",
        "code" => "workflow code",
        "tags" => ["tag1"]
      }

      assert {:error, %Ecto.Changeset{} = changeset} =
               WorkflowTemplates.create_template(attrs)

      assert "can't be blank" in errors_on(changeset).workflow_id
    end

    test "returns error when description is too long" do
      workflow = insert(:workflow)
      long_description = String.duplicate("a", 1001)

      attrs = %{
        "name" => "My Template",
        "code" => "workflow code",
        "workflow_id" => workflow.id,
        "description" => long_description,
        "tags" => ["tag1"]
      }

      assert {:error, %Ecto.Changeset{} = changeset} =
               WorkflowTemplates.create_template(attrs)

      assert "Description must be less than 1000 characters" in errors_on(
               changeset
             ).description
    end

    test "returns error when workflow_id is invalid" do
      attrs = %{
        "name" => "My Template",
        "code" => "workflow code",
        "workflow_id" => Ecto.UUID.generate(),
        "tags" => ["tag1"]
      }

      assert {:error, %Ecto.Changeset{} = changeset} =
               WorkflowTemplates.create_template(attrs)

      assert "does not exist" in errors_on(changeset).workflow
    end

    test "returns error when tags are invalid" do
      workflow = insert(:workflow)

      attrs = %{
        "name" => "My Template",
        "code" => "workflow code",
        "workflow_id" => workflow.id,
        "tags" => "not a list"
      }

      assert {:error, %Ecto.Changeset{} = changeset} =
               WorkflowTemplates.create_template(attrs)

      assert "is invalid" in errors_on(changeset).tags
    end
  end

  describe "get_template_by_workflow_id/1" do
    test "returns template when it exists" do
      workflow = insert(:workflow)
      template = insert(:workflow_template, workflow: workflow)

      retrieved_template =
        WorkflowTemplates.get_template_by_workflow_id(workflow.id)

      assert retrieved_template.id == template.id
      assert retrieved_template.name == template.name
      assert retrieved_template.code == template.code
      assert retrieved_template.workflow_id == template.workflow_id
    end

    test "returns nil when no template exists" do
      assert WorkflowTemplates.get_template_by_workflow_id(Ecto.UUID.generate()) ==
               nil
    end
  end

  describe "update_template/2" do
    test "updates a template with valid data" do
      template = insert(:workflow_template)
      attrs = %{"name" => "Updated Name", "code" => "updated code"}

      assert {:ok, %WorkflowTemplate{} = updated_template} =
               WorkflowTemplates.update_template(template, attrs)

      assert updated_template.name == "Updated Name"
      assert updated_template.code == "updated code"
    end

    test "returns error when updating with invalid data" do
      template = insert(:workflow_template)
      attrs = %{"name" => ""}

      assert {:error, %Ecto.Changeset{} = changeset} =
               WorkflowTemplates.update_template(template, attrs)

      assert "can't be blank" in errors_on(changeset).name
    end

    test "returns error when updating with invalid workflow_id" do
      template = insert(:workflow_template)
      attrs = %{"workflow_id" => Ecto.UUID.generate()}

      assert {:error, %Ecto.Changeset{} = changeset} =
               WorkflowTemplates.update_template(template, attrs)

      assert "does not exist" in errors_on(changeset).workflow
    end

    test "returns error when updating with invalid tags" do
      template = insert(:workflow_template)
      attrs = %{"tags" => "not a list"}

      assert {:error, %Ecto.Changeset{} = changeset} =
               WorkflowTemplates.update_template(template, attrs)

      assert "is invalid" in errors_on(changeset).tags
    end
  end

  describe "delete_template/1" do
    test "deletes a template" do
      template = insert(:workflow_template)

      assert {:ok, %WorkflowTemplate{}} =
               WorkflowTemplates.delete_template(template)

      assert WorkflowTemplates.get_template(template.id) == nil
    end
  end

  describe "change_template/2" do
    test "returns a template changeset" do
      template = insert(:workflow_template)
      assert %Ecto.Changeset{} = WorkflowTemplates.change_template(template)
    end
  end

  describe "get_template!/1" do
    test "returns the template when it exists" do
      template = insert(:workflow_template)
      retrieved_template = WorkflowTemplates.get_template!(template.id)
      assert retrieved_template.id == template.id
      assert retrieved_template.name == template.name
      assert retrieved_template.code == template.code
      assert retrieved_template.workflow_id == template.workflow_id
    end

    test "raises when template does not exist" do
      assert_raise Ecto.NoResultsError, fn ->
        WorkflowTemplates.get_template!(Ecto.UUID.generate())
      end
    end
  end

  describe "get_template/1" do
    test "returns the template when it exists" do
      template = insert(:workflow_template)
      retrieved_template = WorkflowTemplates.get_template(template.id)
      assert retrieved_template.id == template.id
      assert retrieved_template.name == template.name
      assert retrieved_template.code == template.code
      assert retrieved_template.workflow_id == template.workflow_id
    end

    test "returns nil when template does not exist" do
      assert WorkflowTemplates.get_template(Ecto.UUID.generate()) == nil
    end
  end

  describe "list_templates/0" do
    test "returns all templates" do
      template1 = insert(:workflow_template)
      template2 = insert(:workflow_template)

      templates = WorkflowTemplates.list_templates()
      assert length(templates) == 2
      assert Enum.any?(templates, fn t -> t.id == template1.id end)
      assert Enum.any?(templates, fn t -> t.id == template2.id end)
    end
  end

  describe "list_workflow_templates/1" do
    test "returns templates for a specific workflow" do
      workflow1 = insert(:workflow)
      workflow2 = insert(:workflow)
      template1 = insert(:workflow_template, workflow: workflow1)
      _template2 = insert(:workflow_template, workflow: workflow2)

      templates = WorkflowTemplates.list_workflow_templates(workflow1)
      assert length(templates) == 1
      assert Enum.at(templates, 0).id == template1.id
    end

    test "returns empty list when workflow has no templates" do
      workflow = insert(:workflow)
      assert [] = WorkflowTemplates.list_workflow_templates(workflow)
    end
  end
end
