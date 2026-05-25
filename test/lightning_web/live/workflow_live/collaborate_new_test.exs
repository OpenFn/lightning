defmodule LightningWeb.WorkflowLive.CollaborateNewTest do
  use LightningWeb.ConnCase, async: false

  import Lightning.Factories
  import Phoenix.LiveViewTest

  describe "sandbox indicator banner data attributes" do
    test "sets root project data attributes when creating workflow in a sandbox the user has full ancestor access to",
         %{conn: conn} do
      user = insert(:user)

      parent_project =
        insert(:project,
          name: "Production Project",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      sandbox =
        insert(:sandbox,
          parent: parent_project,
          name: "test-sandbox",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{sandbox.id}/w/new?method=template"
        )

      assert html =~ "data-root-project-id=\"#{parent_project.id}\""
      assert html =~ "data-root-project-name=\"#{parent_project.name}\""
    end

    test "falls back to the sandbox itself when the user has no access to ancestors",
         %{conn: conn} do
      user = insert(:user)
      parent_project = insert(:project, name: "Production Project")

      sandbox =
        insert(:sandbox,
          parent: parent_project,
          name: "test-sandbox",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{sandbox.id}/w/new?method=template"
        )

      refute html =~ parent_project.name
      assert html =~ "data-root-project-id=\"#{sandbox.id}\""
      assert html =~ "data-root-project-name=\"#{sandbox.name}\""
    end

    test "sets null root project data attributes when creating workflow in root project",
         %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project,
          name: "Production Project",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{project.id}/w/new"
        )

      refute html =~ "data-root-project-id="
      refute html =~ "data-root-project-name="
    end

    test "sets correct root project when creating workflow in a deeply nested sandbox the user has full ancestor access to",
         %{conn: conn} do
      user = insert(:user)

      root_project =
        insert(:project,
          name: "Root Project",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      sandbox_a =
        insert(:sandbox,
          parent: root_project,
          name: "sandbox-a",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      sandbox_b =
        insert(:sandbox,
          parent: sandbox_a,
          name: "sandbox-b",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{sandbox_b.id}/w/new"
        )

      assert html =~ "data-root-project-id=\"#{root_project.id}\""
      assert html =~ "data-root-project-name=\"#{root_project.name}\""

      assert html =~
               "data-project-display-name=\"#{root_project.name}/#{sandbox_a.name}/#{sandbox_b.name}\""
    end

    test "deeply nested sandbox truncates display name at the user's access root when creating workflow",
         %{conn: conn} do
      user = insert(:user)
      root_project = insert(:project, name: "Root Project")

      sandbox_a =
        insert(:sandbox,
          parent: root_project,
          name: "sandbox-a",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      sandbox_b =
        insert(:sandbox,
          parent: sandbox_a,
          name: "sandbox-b",
          project_users: [%{user_id: user.id, role: :owner}]
        )

      conn = log_in_user(conn, user)

      {:ok, _view, html} =
        live(
          conn,
          ~p"/projects/#{sandbox_b.id}/w/new"
        )

      refute html =~ root_project.name
      assert html =~ "data-root-project-id=\"#{sandbox_a.id}\""
      assert html =~ "data-root-project-name=\"#{sandbox_a.name}\""

      assert html =~
               "data-project-display-name=\"#{sandbox_a.name}/#{sandbox_b.name}\""
    end
  end
end
