defmodule LightningWeb.WorkflowLive.NewWorkflowComponentTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  setup %{project: project} do
    # Create 5 distinct templates using factories
    templates = [
      insert(:workflow_template, %{
        name: "Webhook Data Sync",
        description: "Sync data from webhook to database",
        tags: ["webhook", "sync", "database"],
        workflow: build(:workflow, project: project)
      }),
      insert(:workflow_template, %{
        name: "Scheduled Report Generator",
        description: "Generate reports on a schedule",
        tags: ["cron", "reports", "scheduled"],
        workflow: build(:workflow, project: project)
      }),
      insert(:workflow_template, %{
        name: "API Data Processor",
        description: "Process data from external APIs",
        tags: ["api", "data", "processing"],
        workflow: build(:workflow, project: project)
      }),
      insert(:workflow_template, %{
        name: "File Upload Handler",
        description: "Handle and process file uploads",
        tags: ["files", "upload", "storage"],
        workflow: build(:workflow, project: project)
      }),
      insert(:workflow_template, %{
        name: "Notification System",
        description: "Send notifications via email and SMS",
        tags: ["notifications", "email", "sms"],
        workflow: build(:workflow, project: project)
      })
    ]

    %{templates: templates}
  end

  describe "workflow creation methods" do
    test "displays template and import options", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Initial state should show template selection
      assert view |> element("#create-workflow-from-template") |> has_element?()
      assert view |> element("#import-workflow-btn") |> has_element?()
      refute view |> element("#workflow-importer") |> has_element?()
    end

    test "switches to import view when import button is clicked", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Click import button
      html = view |> element("#import-workflow-btn") |> render_click()

      # Should now show the import view
      assert html =~ "Upload a file"
      assert html =~ "or drag and drop"
      assert view |> element("#workflow-importer") |> has_element?()
      assert view |> element("#workflow-dropzone") |> has_element?()
      assert view |> element("#workflow-file") |> has_element?()
    end

    test "can switch back to template view from import view", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Switch to import view
      view |> element("#import-workflow-btn") |> render_click()

      # Click back button
      _html = view |> element("#move-back-to-templates-btn") |> render_click()

      # Should show template selection again
      assert view |> element("#create-workflow-from-template") |> has_element?()
      refute view |> element("#workflow-importer") |> has_element?()
    end
  end

  describe "template selection" do
    test "displays available templates", %{conn: conn, project: project} do
      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/w/new")

      assert html =~ "base-webhook"
      assert html =~ "Event-based Workflow"
      assert html =~ "base-cron"
      assert html =~ "Scheduled Workflow"

      # Template selection form should be present
      assert view |> element("#choose-workflow-template-form") |> has_element?()
    end

    test "allows template selection", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Select a template
      assert view
             |> element("#template-input-base-webhook-template")
             |> has_element?()

      assert view
             |> element("#template-input-base-cron-template")
             |> has_element?()
    end

    test "searches templates by name", %{
      conn: conn,
      project: project,
      templates: templates
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Search for each template name
      for template <- templates do
        view
        |> form("#search-templates-form", %{"search" => template.name})
        |> render_change()

        # Should show the template
        assert view
               |> element("#template-input-#{template.id}")
               |> has_element?()

        # Should still show base templates
        assert view
               |> element("#template-input-base-webhook-template")
               |> has_element?()

        assert view
               |> element("#template-input-base-cron-template")
               |> has_element?()
      end

      # Clear search
      view
      |> form("#search-templates-form", %{"search" => ""})
      |> render_change()

      # Should show all templates again
      for template <- templates do
        assert view
               |> element("#template-input-#{template.id}")
               |> has_element?()
      end
    end

    test "searches templates by description", %{
      conn: conn,
      project: project,
      templates: templates
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Search for each template description
      for template <- templates do
        view
        |> form("#search-templates-form", %{"search" => template.description})
        |> render_change()

        # Should show the template
        assert view
               |> element("#template-input-#{template.id}")
               |> has_element?()

        # Should still show base templates
        assert view
               |> element("#template-input-base-webhook-template")
               |> has_element?()

        assert view
               |> element("#template-input-base-cron-template")
               |> has_element?()
      end
    end

    test "searches templates by tags", %{
      conn: conn,
      project: project,
      templates: templates
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Test searching by specific tags
      view
      |> form("#search-templates-form", %{"search" => "webhook"})
      |> render_change()

      # Should show webhook template
      assert view
             |> element(
               "#template-input-#{Enum.find(templates, &(&1.name == "Webhook Data Sync")).id}"
             )
             |> has_element?()

      # Should still show base templates
      assert view
             |> element("#template-input-base-webhook-template")
             |> has_element?()

      assert view
             |> element("#template-input-base-cron-template")
             |> has_element?()

      # Test another tag
      view
      |> form("#search-templates-form", %{"search" => "cron"})
      |> render_change()

      # Should show cron template
      assert view
             |> element(
               "#template-input-#{Enum.find(templates, &(&1.name == "Scheduled Report Generator")).id}"
             )
             |> has_element?()

      # Should still show base templates
      assert view
             |> element("#template-input-base-webhook-template")
             |> has_element?()

      assert view
             |> element("#template-input-base-cron-template")
             |> has_element?()
    end

    test "search is case insensitive", %{
      conn: conn,
      project: project,
      templates: templates
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Search with uppercase
      for template <- templates do
        view
        |> form("#search-templates-form", %{
          "search" => String.upcase(template.name)
        })
        |> render_change()

        # Should still find the template
        assert view
               |> element("#template-input-#{template.id}")
               |> has_element?()

        # Should still show base templates
        assert view
               |> element("#template-input-base-webhook-template")
               |> has_element?()

        assert view
               |> element("#template-input-base-cron-template")
               |> has_element?()
      end
    end

    test "search with no results shows base templates", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Search for non-existent term
      view
      |> form("#search-templates-form", %{"search" => "nonexistent"})
      |> render_change()

      # Should still show base templates
      assert view
             |> element("#template-input-base-webhook-template")
             |> has_element?()

      assert view
             |> element("#template-input-base-cron-template")
             |> has_element?()
    end

    test "search with partial matches", %{
      conn: conn,
      project: project,
      templates: templates
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Search with partial word
      for template <- templates do
        view
        |> form("#search-templates-form", %{
          "search" => String.slice(template.name, 0, 3)
        })
        |> render_change()

        # Should show matching templates
        assert view
               |> element("#template-input-#{template.id}")
               |> has_element?()

        assert view
               |> element("#template-input-base-webhook-template")
               |> has_element?()

        assert view
               |> element("#template-input-base-cron-template")
               |> has_element?()
      end
    end
  end

  describe "workflow import" do
    test "shows file upload interface", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Switch to import view
      html = view |> element("#import-workflow-btn") |> render_click()

      # Verify upload interface elements
      assert html =~ "Upload a file"
      assert html =~ "or drag and drop"
      assert html =~ "YML or YAML, up to 8MB"
      assert view |> element("#workflow-dropzone") |> has_element?()
      assert view |> element("#workflow-file") |> has_element?()
    end

    test "dropzone has proper attributes for drag and drop", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Switch to import view
      view |> element("#import-workflow-btn") |> render_click()

      # Verify dropzone has necessary attributes for the JavaScript hook
      assert view
             |> element(
               "#workflow-dropzone[phx-hook='FileDropzone'][data-target='#workflow-file']"
             )
             |> has_element?()
    end
  end
end
