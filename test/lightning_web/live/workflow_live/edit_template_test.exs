defmodule LightningWeb.WorkflowLive.EditTemplateTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories
  import Lightning.WorkflowLive.Helpers

  setup :register_and_log_in_support_user
  setup :create_project_for_current_user
  setup :create_workflow

  describe "template publishing" do
    test "publishes a new template", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}/legacy?m=code"
        )

      render_hook(view, "workflow_code_generated", %{
        "code" => "test workflow code",
        "code_with_ids" => "test workflow code with ids"
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
      assert is_nil(template.positions)
    end

    test "saves node positions to templates", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      workflow_positions = %{"some-uuid" => %{"x" => 100, "y" => 100}}

      workflow
      |> Ecto.Changeset.change(%{positions: workflow_positions})
      |> Lightning.Repo.update!()

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}/legacy?m=code"
        )

      render_hook(view, "workflow_code_generated", %{
        "code" => "test workflow code",
        "code_with_ids" => "test workflow code with ids"
      })

      view |> element("#publish-template-btn") |> render_click()

      assert view
             |> form("#workflow-template-form")
             |> render_submit(%{
               "workflow_template" => %{
                 "name" => "My Template",
                 "description" => "A template description",
                 "tags" => "tag1,tag2"
               }
             }) =~
               "Workflow published as template"

      template =
        Lightning.WorkflowTemplates.get_template_by_workflow_id(workflow.id)

      assert template.name == "My Template"
      assert template.description == "A template description"
      assert template.tags == ["tag1", "tag2"]
      assert template.positions == workflow_positions
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
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}/legacy?m=code"
        )

      render_hook(view, "workflow_code_generated", %{
        "code" => "test workflow code",
        "code_with_ids" => "test workflow code with ids"
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
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}/legacy?m=code"
        )

      render_hook(view, "workflow_code_generated", %{
        "code" => "test workflow code",
        "code_with_ids" => "test workflow code with ids"
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
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}/legacy?m=code"
        )

      render_hook(view, "workflow_code_generated", %{
        "code" => "test workflow code",
        "code_with_ids" => "test workflow code with ids"
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
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}/legacy?m=code"
        )

      render_hook(view, "workflow_code_generated", %{
        "code" => "test workflow code",
        "code_with_ids" => "test workflow code with ids"
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
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}/legacy?m=code"
        )

      render_hook(view, "workflow_code_generated", %{
        "code" => "test workflow code",
        "code_with_ids" => "test workflow code with ids"
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
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}/legacy?m=code"
        )

      render_hook(view, "workflow_code_generated", %{
        "code" => "test workflow code",
        "code_with_ids" => "test workflow code with ids"
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
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}/legacy?m=code"
        )

      render_hook(view, "workflow_code_generated", %{
        "code" => "test workflow code",
        "code_with_ids" => "test workflow code with ids"
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

    test "does not show publish button for non-support users", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      # Create a non-support user and add them to the project
      user = insert(:user, support_user: false)
      insert(:project_user, user: user, project: project, role: :editor)
      conn = log_in_user(conn, user)

      {:ok, view, _html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/#{workflow.id}/legacy?m=code"
        )

      render_hook(view, "workflow_code_generated", %{
        "code" => "test workflow code",
        "code_with_ids" => "test workflow code with ids"
      })

      refute view |> element("#publish-template-btn") |> has_element?()
    end
  end

  describe "tag input component" do
    test "renders with empty tags" do
      html =
        render_component(&LightningWeb.Components.NewInputs.input/1, %{
          type: "tag",
          id: "test-tags",
          name: "test_tags",
          value: []
        })

      assert html =~ ~s{id="test-tags-container"}
      assert html =~ ~s{id="test-tags_raw"}
      assert html =~ ~s{id="test-tags"}
      assert html =~ ~s{value=""}
      assert html =~ ~s{class="tag-list mt-2"}
      refute html =~ ~s{<span id="tag-}
    end

    test "renders with list of tags" do
      html =
        render_component(&LightningWeb.Components.NewInputs.input/1, %{
          type: "tag",
          id: "test-tags",
          name: "test_tags",
          value: ["tag1", "tag2", "tag3"]
        })

      assert html =~ ~s{id="test-tags-container"}
      assert html =~ ~s{id="test-tags_raw"}
      assert html =~ ~s{id="test-tags"}
      assert html =~ ~s{value="tag1,tag2,tag3"}

      assert html =~
               ~s{<span id="tag-tag1" class="inline-flex items-center rounded-md bg-blue-50 p-2 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10 mr-1 my-1" data-tag="tag1">}

      assert html =~
               ~s{<span id="tag-tag2" class="inline-flex items-center rounded-md bg-blue-50 p-2 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10 mr-1 my-1" data-tag="tag2">}

      assert html =~
               ~s{<span id="tag-tag3" class="inline-flex items-center rounded-md bg-blue-50 p-2 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10 mr-1 my-1" data-tag="tag3">}
    end

    test "renders with comma-separated string of tags" do
      html =
        render_component(&LightningWeb.Components.NewInputs.input/1, %{
          type: "tag",
          id: "test-tags",
          name: "test_tags",
          value: "tag1,tag2,tag3"
        })

      assert html =~ ~s{id="test-tags-container"}
      assert html =~ ~s{id="test-tags_raw"}
      assert html =~ ~s{id="test-tags"}
      assert html =~ ~s{value="tag1,tag2,tag3"}
      assert html =~ ~s{class="tag-list mt-2"}

      assert html =~
               ~s{<span id="tag-tag1" class="inline-flex items-center rounded-md bg-blue-50 p-2 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10 mr-1 my-1" data-tag="tag1">}

      assert html =~
               ~s{<span id="tag-tag2" class="inline-flex items-center rounded-md bg-blue-50 p-2 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10 mr-1 my-1" data-tag="tag2">}

      assert html =~
               ~s{<span id="tag-tag3" class="inline-flex items-center rounded-md bg-blue-50 p-2 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10 mr-1 my-1" data-tag="tag3">}
    end

    test "renders with trimmed tags" do
      html =
        render_component(&LightningWeb.Components.NewInputs.input/1, %{
          type: "tag",
          id: "test-tags",
          name: "test_tags",
          value: " tag1 , tag2 , tag3 "
        })

      assert html =~ ~s{id="test-tags-container"}
      assert html =~ ~s{id="test-tags_raw"}
      assert html =~ ~s{id="test-tags"}
      assert html =~ ~s{value="tag1,tag2,tag3"}
      assert html =~ ~s{class="tag-list mt-2"}

      assert html =~
               ~s{<span id="tag-tag1" class="inline-flex items-center rounded-md bg-blue-50 p-2 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10 mr-1 my-1" data-tag="tag1">}

      assert html =~
               ~s{<span id="tag-tag2" class="inline-flex items-center rounded-md bg-blue-50 p-2 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10 mr-1 my-1" data-tag="tag2">}

      assert html =~
               ~s{<span id="tag-tag3" class="inline-flex items-center rounded-md bg-blue-50 p-2 text-xs font-medium text-gray-600 ring-1 ring-inset ring-gray-500/10 mr-1 my-1" data-tag="tag3">}
    end

    test "renders with label and required indicator" do
      html =
        render_component(&LightningWeb.Components.NewInputs.input/1, %{
          type: "tag",
          id: "test-tags",
          name: "test_tags",
          label: "Tags",
          required: true
        })

      assert html =~ ~s{<label for="test-tags"}
      assert html =~ ~s{Tags}
      assert html =~ ~s{<span class="text-red-500"> *</span>}
    end

    test "renders with sublabel" do
      html =
        render_component(&LightningWeb.Components.NewInputs.input/1, %{
          type: "tag",
          id: "test-tags",
          name: "test_tags",
          sublabel: "Add tags separated by commas"
        })

      assert html =~ ~s{<small class="mb-2 block text-xs text-gray-600">}
      assert html =~ ~s{Add tags separated by commas}
    end

    test "renders with placeholder" do
      html =
        render_component(&LightningWeb.Components.NewInputs.input/1, %{
          type: "tag",
          id: "test-tags",
          name: "test_tags",
          placeholder: "Enter tags..."
        })

      assert html =~ ~s{placeholder="Enter tags..."}
    end

    test "renders with errors" do
      html =
        render_component(&LightningWeb.Components.NewInputs.input/1, %{
          type: "tag",
          id: "test-tags",
          name: "test_tags",
          errors: ["Tags are required"]
        })

      assert html =~
               ~s{border-danger-400 focus:border-danger-400 focus:outline-danger-400}

      assert html =~ ~s{Tags are required}
    end

    test "renders with standalone mode" do
      html =
        render_component(&LightningWeb.Components.NewInputs.input/1, %{
          type: "tag",
          id: "test-tags",
          name: "test_tags",
          standalone: true
        })

      assert html =~ ~s{data-standalone-mode}
    end
  end
end
