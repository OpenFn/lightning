defmodule LightningWeb.WorkflowLive.IndexTest do
  use LightningWeb.ConnCase, async: true
  import Phoenix.LiveViewTest

  import Lightning.Factories
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

    test "lists all workflows for a project", %{
      conn: conn,
      project: project
    } do
      workflow_one = insert(:workflow, project: project, name: "One")
      workflow_two = insert(:workflow, project: project, name: "Two")

      {:ok, view, html} = live(conn, ~p"/projects/#{project.id}/w")

      assert html =~ "Create new workflow"

      assert view
             |> has_link?(
               ~p"/projects/#{project.id}/w/#{workflow_one.id}",
               "One"
             )

      assert view
             |> has_link?(
               ~p"/projects/#{project.id}/w/#{workflow_two.id}",
               "Two"
             )
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

      refute view
             |> has_delete_workflow_link?(workflow),
             "shouldn't have a delete link on the page"

      assert view |> render_click("delete_workflow", %{"id" => workflow.id}) =~
               "You are not authorized to perform this action.",
             "shouldn't be able to delete a workflow by sending an event"
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
