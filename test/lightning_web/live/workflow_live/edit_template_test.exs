defmodule LightningWeb.WorkflowLive.EditTemplateTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories
  import Lightning.WorkflowLive.Helpers

  setup :register_and_log_in_user
  setup :create_project_for_current_user
  setup :create_workflow

  describe "template publishing" do
    test "publishes a new template", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}?m=code")

      render_hook(view, "workflow_code_generated", %{
        "code" => "test workflow code"
      })

      view |> element("#publish-template-btn") |> render_click()

      # Send tags in the form submit directly
      template_params = %{
        "workflow_template" => %{
          "name" => "My Template",
          "description" => "A template description",
          "tags" => "tag1,tag2"
        }
      }

      assert view
             |> form("#workflow-template-form")
             |> render_submit(template_params) =~
               "Workflow published as template"

      template =
        Lightning.WorkflowTemplates.get_template_by_workflow_id(workflow.id)

      assert template.name == "My Template"
      assert template.description == "A template description"
      assert template.tags == ["tag1", "tag2"]
    end

    test "updates an existing template", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      template =
        insert(:workflow_template,
          workflow: workflow,
          name: "Old Name",
          tags: []
        )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}?m=code")

      render_hook(view, "workflow_code_generated", %{
        "code" => "test workflow code"
      })

      view |> element("#publish-template-btn") |> render_click()

      template_params = %{
        "workflow_template" => %{
          "name" => "Updated Name",
          "description" => "Updated description",
          "tags" => "updated,tags"
        }
      }

      assert view
             |> form("#workflow-template-form")
             |> render_submit(template_params) =~ "Workflow template updated"

      updated_template = Lightning.WorkflowTemplates.get_template(template.id)
      assert updated_template.name == "Updated Name"
      assert updated_template.description == "Updated description"
      assert updated_template.tags == ["updated", "tags"]
    end

    test "validates template form", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}?m=code")

      render_hook(view, "workflow_code_generated", %{
        "code" => "test workflow code"
      })

      view |> element("#publish-template-btn") |> render_click()

      assert view
             |> form("#workflow-template-form", %{
               "workflow_template" => %{"name" => ""}
             })
             |> render_submit() =~ "This field can&#39;t be blank"
    end

    test "cancels template publishing", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}?m=code")

      render_hook(view, "workflow_code_generated", %{
        "code" => "test workflow code"
      })

      view |> element("#publish-template-btn") |> render_click()

      view |> element("#cancel-template-publish") |> render_click()

      refute view |> element("#workflow-template-form") |> has_element?()
    end

    test "disables publish button when workflow has unsaved changes", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}?m=code")

      render_hook(view, "workflow_code_generated", %{
        "code" => "test workflow code"
      })

      view
      |> form("#workflow-form")
      |> render_change(workflow: %{name: "New Name"})

      assert view |> element("#publish-template-btn[disabled]") |> has_element?()
    end

    test "validates template name length", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}?m=code")

      render_hook(view, "workflow_code_generated", %{
        "code" => "test workflow code"
      })

      view |> element("#publish-template-btn") |> render_click()

      long_name = String.duplicate("a", 256)

      assert view
             |> form("#workflow-template-form", %{
               "workflow_template" => %{"name" => long_name}
             })
             |> render_submit() =~ "Name must be less than 255 characters"
    end

    test "validates template description length", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}?m=code")

      render_hook(view, "workflow_code_generated", %{
        "code" => "test workflow code"
      })

      view |> element("#publish-template-btn") |> render_click()

      long_description = String.duplicate("a", 1001)

      assert view
             |> form("#workflow-template-form", %{
               "workflow_template" => %{
                 "name" => "Valid Name",
                 "description" => long_description
               }
             })
             |> render_submit() =~
               "Description must be less than 1000 characters"
    end

    test "prevents publishing with unsaved changes", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}?m=code")

      render_hook(view, "workflow_code_generated", %{
        "code" => "test workflow code"
      })

      # Make unsaved changes
      view
      |> form("#workflow-form")
      |> render_change(workflow: %{name: "New Name"})

      # Verify the publish button is disabled
      assert view |> element("#publish-template-btn[disabled]") |> has_element?()

      # Verify the template form is not rendered
      refute view |> element("#workflow-template-form") |> has_element?()
    end
  end
end
