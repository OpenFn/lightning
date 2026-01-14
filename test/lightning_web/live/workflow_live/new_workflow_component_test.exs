defmodule LightningWeb.WorkflowLive.NewWorkflowComponentTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories
  import Lightning.WorkflowLive.Helpers

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  setup %{project: project} = tags do
    if Map.get(tags, :stub_apollo, true) do
      Lightning.AiAssistantHelpers.stub_online()
    end

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

  defp skip_disclaimer(user, read_at \\ DateTime.utc_now() |> DateTime.to_unix()) do
    Ecto.Changeset.change(user, %{
      preferences: %{"ai_assistant.disclaimer_read_at" => read_at}
    })
    |> Lightning.Repo.update!()
  end

  describe "workflow creation methods" do
    @tag stub_apollo: false
    test "displays template and import options", %{conn: conn, project: project} do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

      # Initial state should show template selection
      assert view |> element("#create-workflow-from-template") |> has_element?()
      assert view |> element("#import-workflow-btn") |> has_element?()
      refute view |> element("#workflow-importer") |> has_element?()
    end

    @tag stub_apollo: false
    test "switches to import view when import button is clicked", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

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
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

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
      {:ok, view, html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

      assert html =~ "base-webhook"
      assert html =~ "Event-based Workflow"
      assert html =~ "base-cron"
      assert html =~ "Scheduled Workflow"

      # Template selection form should be present
      assert view |> element("#choose-workflow-template-form") |> has_element?()
    end

    test "allows template selection", %{conn: conn, project: project} do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

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
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

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
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

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
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

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
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

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
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

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
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

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
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

      # Switch to import view
      html = view |> element("#import-workflow-btn") |> render_click()

      # Verify upload interface elements
      assert html =~ "Upload a file"
      assert html =~ "or drag and drop"
      assert html =~ "YML or YAML, up to 8MB"
      assert view |> element("#workflow-dropzone") |> has_element?()
      assert view |> element("#workflow-file") |> has_element?()
    end

    @tag stub_apollo: false
    test "dropzone has proper attributes for drag and drop", %{
      conn: conn,
      project: project
    } do
      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> "http://localhost:4001"
        :ai_assistant_api_key -> "ai_assistant_api_key"
      end)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

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

  describe "AI method integration" do
    @tag stub_apollo: false
    test "switching to AI method without search term shows AI interface", %{
      conn: conn,
      project: project,
      user: user
    } do
      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> "http://localhost:4001"
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

      ai_assistant = element(view, "#new-workflow-panel-assistant")

      refute has_element?(ai_assistant)

      skip_disclaimer(user)

      view
      |> element("#template-label-ai-dynamic-template")
      |> render_click()

      assert has_element?(ai_assistant)

      html = render(ai_assistant)

      assert html =~ "Start a conversation to see your chat history appear here"
    end

    @tag stub_apollo: false
    test "switching to AI method with search term creates session and shows AI interface",
         %{
           conn: conn,
           project: project,
           user: user
         } do
      Mox.stub(Lightning.MockConfig, :apollo, fn
        :endpoint -> "http://localhost:4001"
        :ai_assistant_api_key -> "ai_assistant_api_key"
        :timeout -> 5_000
      end)

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

      ai_assistant = element(view, "#new-workflow-panel-assistant")

      refute has_element?(ai_assistant)

      view
      |> form("#search-templates-form", %{"search" => "sync data from API"})
      |> render_change()

      skip_disclaimer(user)

      view
      |> element("#template-label-ai-dynamic-template")
      |> render_click()

      assert has_element?(ai_assistant)

      html = render(ai_assistant)

      assert html =~ "sync data from API"
    end

    test "AI template card displays search term correctly", %{
      conn: conn,
      project: project
    } do
      Oban.Testing.with_testing_mode(:manual, fn ->
        Mox.stub(Lightning.MockConfig, :apollo, fn key ->
          case key do
            :endpoint -> "http://localhost:3000"
            :ai_assistant_api_key -> "api_key"
            :timeout -> 5_000
          end
        end)

        {:ok, view, _html} =
          live(conn, ~p"/projects/#{project.id}/w/new/legacy")

        view
        |> form("#search-templates-form", %{"search" => "process webhook data"})
        |> render_change()

        build_with_button = element(view, "#template-label-ai-dynamic-template")

        html = render(build_with_button)
        assert html =~ "process webhook data"
        assert html =~ "Build with AI ✨"

        sessions_before =
          Lightning.AiAssistant.list_sessions(project)
          |> Map.get(:sessions)

        assert Enum.empty?(sessions_before)

        build_with_button |> render_click()

        assert view |> element("#create_workflow_via_ai") |> has_element?()

        sessions_after =
          Lightning.AiAssistant.list_sessions(project)
          |> Map.get(:sessions)

        refute Enum.empty?(sessions_after)

        assert sessions_after |> Enum.any?(&(&1.title == "process webhook data"))
      end)
    end

    test "AI template card shows default text when no search term", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

      html = render(view)
      assert html =~ "Build with AI ✨"
      assert html =~ "Build your workflow using the AI assistant"
    end

    test "can switch back from AI method to templates", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

      view |> element("#template-label-ai-dynamic-template") |> render_click()

      assert view |> element("#create_workflow_via_ai") |> has_element?()

      html = view |> element("#move-back-to-templates-btn") |> render_click()

      assert html =~ "create-workflow-from-template"
      assert view |> element("#create-workflow-from-template") |> has_element?()
      refute view |> element("#create_workflow_via_ai") |> has_element?()
    end
  end

  describe "template selection events" do
    test "selecting a template notifies parent liveview", %{
      conn: conn,
      project: project,
      templates: [%{id: id, code: code} | _]
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

      view
      |> element("#choose-workflow-template-form")
      |> render_change(%{"template_id" => id})

      view |> has_element?("#selected-template-label-#{id}")

      assert_push_event(view, "template_selected", %{template: ^code})
    end

    test "selecting different templates changes the selection", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

      view
      |> element("#choose-workflow-template-form")
      |> render_change(%{"template_id" => "base-webhook-template"})

      assert_push_event(view, "template_selected", %{template: webhook_template})

      view
      |> element("#choose-workflow-template-form")
      |> render_change(%{"template_id" => "base-cron-template"})

      assert_push_event(view, "template_selected", %{template: cron_template})

      refute webhook_template == cron_template
      assert cron_template =~ "Scheduled Workflow"
      assert webhook_template =~ "Event-based Workflow"
    end
  end

  describe "workflow creation validation" do
    test "create button is disabled when no template selected", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

      assert view
             |> element("#create_workflow_btn[disabled]")
             |> has_element?()
    end

    test "create button is enabled when template is selected", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

      {view, _parsed_template} = select_template(view, "base-webhook-template")

      refute view
             |> element("#create_workflow_btn[disabled]")
             |> has_element?()

      element(view, "#create_workflow_btn") |> render_click()

      refute element(view, "#new-workflow-panel")
             |> has_element?()
    end

    test "clicking create without template shows error message", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

      assert element(view, "#create_workflow_btn[disabled]") |> has_element?()

      view
      |> render_click("save", %{})

      assert render(view) =~ "Workflow could not be saved"
    end

    test "create button disabled in import mode when validation fails", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

      element(view, "#import-workflow-btn") |> render_click()

      assert_patch(
        view,
        ~p"/projects/#{project.id}/w/new/legacy?method=import"
      )

      assert view
             |> element("#create_workflow_btn[disabled]")
             |> has_element?()

      view
      |> with_target("#new-workflow-panel")
      |> render_click("create_workflow", %{})
    end

    test "create button disabled in AI mode when no template generated", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/new/legacy")

      view |> element("#template-label-ai-dynamic-template") |> render_click()

      assert_patch(view, ~p"/projects/#{project.id}/w/new/legacy?method=ai")

      assert view
             |> element("#create_workflow_btn[disabled]")
             |> has_element?()

      view
      |> render_click("save")

      assert render(view) =~
               "Workflow could not be saved"
    end
  end
end
