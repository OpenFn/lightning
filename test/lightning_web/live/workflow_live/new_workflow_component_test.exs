defmodule LightningWeb.WorkflowLive.NewWorkflowComponentTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "workflow creation methods" do
    test "displays template and import options", %{conn: conn, project: project} do
      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Initial state should show template selection
      assert html =~ "Create workflow"
      assert view |> element("#create-workflow-from-template") |> has_element?()
      assert view |> element("#import-workflow-btn") |> has_element?()
      refute view |> element("#workflow-importer") |> has_element?()
    end

    test "switches to import view when import button is clicked", %{conn: conn, project: project} do
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

    test "can switch back to template view from import view", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Switch to import view
      view |> element("#import-workflow-btn") |> render_click()

      # Click back button
      html = view |> element("#move-back-to-templates-btn") |> render_click()

      # Should show template selection again
      assert html =~ "Create workflow"
      assert view |> element("#create-workflow-from-template") |> has_element?()
      refute view |> element("#workflow-importer") |> has_element?()
    end
  end

  describe "template selection" do
    test "displays available templates", %{conn: conn, project: project} do
      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/w/new")

      assert html =~ "base-webhook"
      assert html =~ "webhook triggered workflow"
      assert html =~ "base-cron"
      assert html =~ "cron triggered workflow"

      # Template selection form should be present
      assert view |> element("#choose-workflow-template-form") |> has_element?()
    end

    test "allows template selection", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Select a template
      assert view |> element("#template-input-base-webhook-template") |> has_element?()
      assert view |> element("#template-input-base-cron-template") |> has_element?()
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

    test "dropzone has proper attributes for drag and drop", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w/new")

      # Switch to import view
      view |> element("#import-workflow-btn") |> render_click()

      # Verify dropzone has necessary attributes for the JavaScript hook
      assert view
             |> element("#workflow-dropzone[phx-hook='FileDropzone'][data-target='#workflow-file']")
             |> has_element?()
    end
  end
end
