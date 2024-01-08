defmodule LightningWeb.WorkflowLive.IndexTest do
  use LightningWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  import Lightning.Factories
  import Lightning.WorkflowsFixtures
  import Lightning.WorkflowLive.Helpers

  setup :register_and_log_in_user
  setup :create_project_for_current_user
  setup :create_workflow

  describe "index" do
    test "renders a list of workflows", %{conn: conn, project: project} do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      assert view
             |> element("#workflows-#{project.id}", "No workflows yet")
    end

    test "only users with MFA enabled can access workflows for a project with MFA requirement",
         %{
           conn: conn
         } do
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))
      conn = log_in_user(conn, user)

      project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: user, role: :admin}]
        )

      create_workflow(%{project: project})

      {:ok, view, _html} = live(conn, ~p"/projects/#{project}/w")

      assert element(view, "#workflows-#{project.id}", "No workflows yet")

      ~w(editor viewer admin)a
      |> Enum.each(fn role ->
        {conn, _user} = setup_project_user(conn, project, role)

        assert {:error, {:redirect, %{to: "/mfa_required"}}} =
                 live(conn, ~p"/projects/#{project}/w")
      end)
    end

    test "shows the Dashboard for a project", %{
      conn: conn,
      project: project
    } do
      workflow1 =
        complex_workflow_with_runs(
          name: "One",
          project: project,
          last_workorder_failed: true
        )

      workflow2 =
        complex_workflow_with_runs(
          name: "Two",
          project: project,
          last_workorder_failed: false
        )

      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/w")

      assert Regex.match?(~r/Dashboard.*h1>/s, html)

      # Metrics
      # 8 total workorders
      # 16 total runs (2 pending, 4 failed)
      # 10 successful runs out of 14 (71.43%)
      # 2 work orders failed (25.0%)
      assert Regex.match?(~r/Work Orders.*">\s*8/s, html)
      assert Regex.match?(~r/Runs.*>\s*16.*">\s*\(2 pending\)/s, html)
      assert Regex.match?(~r/Successful Runs.*">\s*10.*">\s*\(71.43%\)/s, html)

      assert Regex.match?(
               ~r/Work Orders in failed state.*">\s*2.*">\s*\(25.0%\)/s,
               html
             )

      # Header
      assert Regex.match?(~r/Workflows.*h3>/s, html)

      assert Regex.match?(
               ~r/<button.*id="open-modal-button".*Create new workflow.*button>/s,
               html
             )

      # Workflow links
      assert view
             |> has_link?(
               ~p"/projects/#{project.id}/w/#{workflow1.id}",
               "One"
             )

      assert view
             |> has_link?(
               ~p"/projects/#{project.id}/w/#{workflow2.id}",
               "Two"
             )

      # Work orders links
      failed_filter_pattern =
        "filters[cancelled]=true.*filters[crashed]=true.*filters[exception]=true.*filters[failed]=true.*filters[killed]=true.*filters[lost]=true"

      assert html
             |> has_runs_link_pattern?(
               project,
               failed_filter_pattern
             )

      refute html
             |> has_runs_link_pattern?(
               project,
               "filters[pending]=true"
             )

      refute html
             |> has_runs_link_pattern?(
               project,
               "filters[running]=true"
             )

      refute html
             |> has_runs_link_pattern?(
               project,
               "filters[success]=true"
             )

      workorders_count = 4

      assert view
             |> has_link?(
               ~p"/projects/#{project.id}/runs?filters[workflow_id]=#{workflow1.id}",
               "#{workorders_count}"
             )

      assert view
             |> has_link?(
               ~p"/projects/#{project.id}/runs?filters[workflow_id]=#{workflow2.id}",
               "#{workorders_count}"
             )

      # Failed runs links
      assert html
             |> has_runs_link_pattern?(
               project,
               "filters[workflow_id]=#{workflow1.id}.*#{failed_filter_pattern}"
             )

      assert html
             |> has_runs_link_pattern?(
               project,
               "filters[workflow_id]=#{workflow2.id}.*#{failed_filter_pattern}"
             )

      # 5 successful runs out of 8 (62.5%)
      assert Regex.match?(~r/(8 runs.*62.5% success)/s, html)
    end
  end

  describe "creating workflows" do
    @tag role: :viewer
    test "users with viewer role cannot create a workflow", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      {:ok, _, html} =
        view
        |> form("#new_workflow", new_workflow: %{name: "New workflow"})
        |> render_submit()
        |> follow_redirect(conn)
        |> follow_redirect(conn)

      assert html =~ "You are not authorized to perform this action."
    end

    @tag role: :editor
    test "users with editor role can create a workflow", %{
      conn: conn,
      project: project
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")
      query_params = %{name: "New workflow"}
      query_string = URI.encode_query(query_params)

      {:ok, _, html} =
        view
        |> form("#new_workflow", new_workflow: %{name: "New workflow"})
        |> render_submit()
        |> follow_redirect(
          conn,
          "/projects/#{project.id}/w/new?#{query_string}"
        )

      assert html =~ "New workflow"
    end

    test "only users with MFA enabled can create workflows for a project with MFA requirement",
         %{
           conn: conn
         } do
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))
      conn = log_in_user(conn, user)

      project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: user, role: :admin}]
        )

      create_workflow(%{project: project})

      {:ok, _view, html} = live(conn, ~p"/projects/#{project}/w")

      assert html =~ "Create new workflow"

      ~w(editor admin)a
      |> Enum.each(fn role ->
        {conn, _user} = setup_project_user(conn, project, role)

        assert {:error, {:redirect, %{to: "/mfa_required"}}} =
                 live(conn, ~p"/projects/#{project}/w")
      end)
    end
  end

  describe "deleting workflows" do
    @tag role: :viewer
    test "users with viewer role cannot delete a workflow", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      refute view |> has_delete_workflow_link?(workflow)

      assert view |> render_click("delete_workflow", %{"id" => workflow.id}) =~
               "You are not authorized to perform this action."
    end

    @tag role: :editor
    test "users with editor role can delete a workflow", %{
      conn: conn,
      project: project,
      workflow: workflow
    } do
      {:ok, view, _html} = live(conn, ~p"/projects/#{project.id}/w")

      assert has_workflow_card?(view, workflow)

      assert view |> has_delete_workflow_link?(workflow)

      assert view |> click_delete_workflow(workflow) =~
               "Workflow successfully deleted."

      refute has_workflow_card?(view, workflow)
    end
  end
end
