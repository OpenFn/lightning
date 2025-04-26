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

      # First, simulate adding tags via the tag_action event
      render_hook(view, "tag_action", %{
        "action" => "add",
        "value" => "tag1,tag2"
      })

      # Then submit the form without specifying tags (they're already set)
      template_params = %{
        "workflow_template" => %{
          "name" => "My Template",
          "description" => "A template description"
        }
      }

      assert view
             |> form("#workflow-template-form", template_params)
             |> render_submit() =~ "Workflow published as template"

      template =
        Lightning.WorkflowTemplates.get_template_by_workflow_id(workflow.id)

      assert template.name == "My Template"
      assert template.description == "A template description"
      assert template.tags == Enum.sort(["tag1", "tag2"])
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

      render_hook(view, "tag_action", %{
        "action" => "add",
        "value" => "updated,tags"
      })

      template_params = %{
        "workflow_template" => %{
          "name" => "Updated Name",
          "description" => "Updated description"
        }
      }

      assert view
             |> form("#workflow-template-form", template_params)
             |> render_submit() =~ "Workflow template updated"

      updated_template = Lightning.WorkflowTemplates.get_template(template.id)
      assert updated_template.name == "Updated Name"
      assert updated_template.description == "Updated description"
      assert updated_template.tags == Enum.sort(["updated", "tags"])
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

    test "handles tag removal", %{
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

      # First add some tags
      render_hook(view, "tag_action", %{
        "action" => "add",
        "value" => "tag1,tag2,tag3"
      })

      # Then remove one
      render_hook(view, "tag_action", %{
        "action" => "remove",
        "value" => "tag2"
      })

      template_params = %{
        "workflow_template" => %{
          "name" => "My Template",
          "description" => "A template description"
        }
      }

      assert view
             |> form("#workflow-template-form", template_params)
             |> render_submit() =~ "Workflow published as template"

      template =
        Lightning.WorkflowTemplates.get_template_by_workflow_id(workflow.id)

      assert template.tags == Enum.sort(["tag1", "tag3"])
    end

    test "handles tag editing", %{
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

      # First add a tag
      render_hook(view, "tag_action", %{
        "action" => "add",
        "value" => "oldtag"
      })

      # Then edit it
      render_hook(view, "tag_action", %{
        "action" => "edit",
        "value" => "oldtag"
      })

      # Simulate user typing new tag
      render_hook(view, "tag_action", %{
        "action" => "add",
        "value" => "newtag"
      })

      template_params = %{
        "workflow_template" => %{
          "name" => "My Template",
          "description" => "A template description"
        }
      }

      assert view
             |> form("#workflow-template-form", template_params)
             |> render_submit() =~ "Workflow published as template"

      template =
        Lightning.WorkflowTemplates.get_template_by_workflow_id(workflow.id)

      assert template.tags == ["newtag"]
    end

    test "handles special characters in tags", %{
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

      render_hook(view, "tag_action", %{
        "action" => "add",
        "value" => "tag-with-hyphen,tag_with_underscore,tag with spaces"
      })

      template_params = %{
        "workflow_template" => %{
          "name" => "My Template",
          "description" => "A template description"
        }
      }

      assert view
             |> form("#workflow-template-form", template_params)
             |> render_submit() =~ "Workflow published as template"

      template =
        Lightning.WorkflowTemplates.get_template_by_workflow_id(workflow.id)

      assert template.tags ==
               Enum.sort([
                 "tag-with-hyphen",
                 "tag_with_underscore",
                 "tag with spaces"
               ])
    end

    test "handles duplicate tags", %{
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

      render_hook(view, "tag_action", %{
        "action" => "add",
        "value" => "duplicate,duplicate,unique"
      })

      template_params = %{
        "workflow_template" => %{
          "name" => "My Template",
          "description" => "A template description"
        }
      }

      assert view
             |> form("#workflow-template-form", template_params)
             |> render_submit() =~ "Workflow published as template"

      template =
        Lightning.WorkflowTemplates.get_template_by_workflow_id(workflow.id)

      assert template.tags == Enum.sort(["duplicate", "unique"])
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

  describe "tag input component" do
    test "includes correct hooks for tag input functionality" do
      html =
        render_component(&LightningWeb.Components.NewInputs.input/1,
          type: "tag",
          value: ["test-tag"],
          name: "tags"
        )

      assert html =~ ~s(phx-hook="TagInput")
      assert html =~ ~s(phx-hook="EditTag")
      assert html =~ ~s(phx-hook="DeleteTag")
      assert html =~ ~s(data-tag="test-tag")
    end

    test "handles string value for tags" do
      html =
        render_component(&LightningWeb.Components.NewInputs.input/1,
          type: "tag",
          value: "tag1,tag2,tag3",
          name: "tags"
        )

      assert html =~ "tag1"
      assert html =~ "tag2"
      assert html =~ "tag3"
    end

    test "handles basic usage" do
      html =
        render_component(&LightningWeb.Components.NewInputs.input/1,
          type: "tag",
          name: "tags"
        )

      assert html =~ ~s(name="tags")
      assert html =~ "tag-input-container"
      assert html =~ "tag-list"
      assert html =~ ~s(phx-hook="TagInput")
    end

    test "accepts list values for tags" do
      html =
        render_component(&LightningWeb.Components.NewInputs.input/1,
          name: "tags",
          type: "tag",
          value: ["tag1", "tag2"]
        )

      assert html =~ "tag1"
      assert html =~ "tag2"
    end

    test "handles invalid value types gracefully" do
      html =
        render_component(&LightningWeb.Components.NewInputs.input/1,
          type: "tag",
          value: %{invalid: "value"},
          name: "tags"
        )

      assert html =~ ~s(<div class="tag-list mt-2">\n    \n  </div>)
    end

    test "includes ID and name attributes correctly" do
      html =
        render_component(&LightningWeb.Components.NewInputs.input/1,
          type: "tag",
          id: "my-custom-id",
          name: "my-custom-name"
        )

      assert html =~ ~s(id="my-custom-id")
      assert html =~ ~s(name="my-custom-name")
    end
  end
end
