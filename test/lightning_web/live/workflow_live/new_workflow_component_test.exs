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
        name: "Nightly Financial Sync",
        description: "Sync data from one financial system to another",
        tags: ["Nightly", "sync", "database", "finance"],
        workflow: build(:workflow, project: project)
      }),
      insert(:workflow_template, %{
        name: "Scheduled Report Generator",
        description: "Generate reports on a schedule",
        tags: ["cron", "reports", "scheduled"],
        workflow: build(:workflow, project: project)
      }),
      insert(:workflow_template, %{
        name: "CommCare to FHIR converter",
        description: "Process data from CommCare and convert to FHIR",
        tags: ["api", "data", "processing", "commcare", "fhir"],
        workflow: build(:workflow, project: project)
      }),
      insert(:workflow_template, %{
        name: "File Upload Handler",
        description: "Handle and process file uploads",
        tags: ["files", "upload", "storage"],
        workflow: build(:workflow, project: project)
      }),
      insert(:workflow_template, %{
        name: "Notification flow",
        description: "Send notifications via email and SMS",
        tags: ["notifications", "email", "sms"],
        workflow: build(:workflow, project: project)
      })
    ]

    %{templates: templates}
  end

  describe "workflow creation methods" do
    test "displays template and import options", %{conn: conn, project: project} do
      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Initial state should show template selection
      assert html =~ "Build your workflow from templates"
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
      html = view |> element("#move-back-to-templates-btn") |> render_click()

      # Should show template selection again
      assert html =~ "Build your workflow from templates"
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
      |> form("#search-templates-form", %{"search" => "finance"})
      |> render_change()

      # Should show financial template
      assert view
             |> element(
               "#template-input-#{Enum.find(templates, &(&1.name == "Nightly Financial Sync")).id}"
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
      |> form("#search-templates-form", %{"search" => "commcare"})
      |> render_change()

      # Should show commcare template
      assert view
             |> element(
               "#template-input-#{Enum.find(templates, &(&1.name == "CommCare to FHIR converter")).id}"
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

    test "comprehensive partial word matching", %{
      conn: conn,
      project: project,
      templates: templates
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Test various partial word matches
      test_cases = [
        # Start of word
        {"nigh", "Nightly Financial Sync"},
        {"sch", "Scheduled Report Generator"},
        {"comm", "CommCare to FHIR converter"},
        {"fil", "File Upload Handler"},
        {"not", "Notification flow"}
      ]

      for {search_term, expected_name} <- test_cases do
        view
        |> form("#search-templates-form", %{"search" => search_term})
        |> render_change()

        # Should find the template with partial match
        assert view
               |> element(
                 "#template-input-#{Enum.find(templates, &(&1.name == expected_name)).id}"
               )
               |> has_element?()
      end
    end

    test "partial string matching within words", %{
      conn: conn,
      project: project,
      templates: templates
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Test partial string matches within words
      test_cases = [
        # Partial matches in names (2+ chars)
        {"night", "Nightly Financial Sync"},
        {"sched", "Scheduled Report Generator"},
        {"commc", "CommCare to FHIR converter"},
        {"uploa", "File Upload Handler"},
        {"notif", "Notification flow"}
      ]

      for {search_term, expected_name} <- test_cases do
        view
        |> form("#search-templates-form", %{"search" => search_term})
        |> render_change()

        # Should find the template with partial string match
        assert view
               |> element(
                 "#template-input-#{Enum.find(templates, &(&1.name == expected_name)).id}"
               )
               |> has_element?()
      end
    end

    test "search results require all terms to match (with fuzzy/partial support)",
         %{
           conn: conn,
           project: project,
           templates: templates
         } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      test_cases = [
        # Single word, exact
        {"nightly", ["Nightly Financial Sync"]},
        {"scheduled", ["Scheduled Report Generator"]},
        {"commcare", ["CommCare to FHIR converter"]},
        {"file", ["File Upload Handler"]},
        {"notification", ["Notification flow"]},
        # Single word, partial
        {"night", ["Nightly Financial Sync"]},
        {"sched", ["Scheduled Report Generator"]},
        {"commc", ["CommCare to FHIR converter"]},
        {"uploa", ["File Upload Handler"]},
        {"notif", ["Notification flow"]},
        # Multi-word, all terms must match (exact or partial)
        {"nightly sync", ["Nightly Financial Sync"]},
        {"sched report", ["Scheduled Report Generator"]},
        {"commcare fhir", ["CommCare to FHIR converter"]},
        {"file handl", ["File Upload Handler"]},
        {"notific sms", ["Notification flow"]},
        # Multi-word, one term does not match (should not show)
        {"nightly banana", []},
        {"commcare scheduled", []},
        {"upload banana", []},
        {"notification xyz", []},
        # No match (should only show base templates)
        {"notarealword", []}
      ]

      for {search_term, expected_names} <- test_cases do
        view
        |> form("#search-templates-form", %{"search" => search_term})
        |> render_change()

        for template <- templates do
          if template.name in expected_names do
            assert view
                   |> element("#template-input-#{template.id}")
                   |> has_element?()
          else
            refute view
                   |> element("#template-input-#{template.id}")
                   |> has_element?()
          end
        end

        # Should always show base templates
        assert view
               |> element("#template-input-base-webhook-template")
               |> has_element?()

        assert view
               |> element("#template-input-base-cron-template")
               |> has_element?()
      end
    end

    test "word order independence", %{
      conn: conn,
      project: project,
      templates: templates
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Test different word orders
      test_cases = [
        {"financial nightly", "Nightly Financial Sync"},
        {"generator report scheduled", "Scheduled Report Generator"},
        {"fhir commcare", "CommCare to FHIR converter"},
        {"handler upload file", "File Upload Handler"},
        {"flow notification", "Notification flow"}
      ]

      for {search_terms, expected_name} <- test_cases do
        view
        |> form("#search-templates-form", %{"search" => search_terms})
        |> render_change()

        # Should find the template regardless of word order
        assert view
               |> element(
                 "#template-input-#{Enum.find(templates, &(&1.name == expected_name)).id}"
               )
               |> has_element?()
      end
    end

    test "multiple word matching", %{
      conn: conn,
      project: project,
      templates: templates
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Test searching with multiple words
      test_cases = [
        {"nightly financial", "Nightly Financial Sync"},
        {"report scheduled", "Scheduled Report Generator"},
        {"commcare fhir", "CommCare to FHIR converter"},
        {"file handler", "File Upload Handler"},
        {"notification email", "Notification flow"}
      ]

      for {search_terms, expected_name} <- test_cases do
        view
        |> form("#search-templates-form", %{"search" => search_terms})
        |> render_change()

        # Should find templates matching all words
        assert view
               |> element(
                 "#template-input-#{Enum.find(templates, &(&1.name == expected_name)).id}"
               )
               |> has_element?()
      end
    end

    test "special character handling", %{
      conn: conn,
      project: project,
      templates: templates
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Test with special characters
      test_cases = [
        {"nightly-financial", "Nightly Financial Sync"},
        {"report.generator", "Scheduled Report Generator"},
        {"commcare_fhir", "CommCare to FHIR converter"},
        {"file/upload", "File Upload Handler"},
        {"notification@flow", "Notification flow"}
      ]

      for {search_terms, expected_name} <- test_cases do
        view
        |> form("#search-templates-form", %{"search" => search_terms})
        |> render_change()

        # Should find templates despite special characters
        assert view
               |> element(
                 "#template-input-#{Enum.find(templates, &(&1.name == expected_name)).id}"
               )
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
