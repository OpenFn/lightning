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
          ~p"/projects/#{sandbox.id}/w/new"
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
          ~p"/projects/#{sandbox.id}/w/new"
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

  describe "create_workflow authorization" do
    setup %{conn: conn} do
      user = insert(:user)
      %{conn: log_in_user(conn, user), user: user}
    end

    test "redirects a viewer away from /w/new with an error flash", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project, project_users: [%{user_id: user.id, role: :viewer}])

      assert {:error, {:redirect, %{to: to, flash: flash}}} =
               live(conn, ~p"/projects/#{project.id}/w/new")

      assert to == ~p"/projects/#{project.id}/w"
      assert flash["error"] == "You are not authorized to perform this action."
    end

    test "redirects a viewer away from /w/new even with an ?id= query param", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project, project_users: [%{user_id: user.id, role: :viewer}])

      workflow = insert(:workflow, project: project)

      assert {:error, {:redirect, %{to: to, flash: flash}}} =
               live(conn, ~p"/projects/#{project.id}/w/new?id=#{workflow.id}")

      assert to == ~p"/projects/#{project.id}/w"
      assert flash["error"] == "You are not authorized to perform this action."
    end

    test "ignores ?id= on /w/new and still mounts a brand new workflow", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project, project_users: [%{user_id: user.id, role: :editor}])

      workflow = insert(:workflow, project: project, name: "Existing workflow")

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project.id}/w/new?id=#{workflow.id}")

      refute html =~ "Existing workflow"
      assert page_title(view) =~ "New Workflow"
    end

    test "lets a role that can create workflows through to the editor", %{
      conn: conn,
      user: user
    } do
      for role <- [:owner, :admin, :editor] do
        project =
          insert(:project, project_users: [%{user_id: user.id, role: role}])

        assert {:ok, _view, _html} =
                 live(conn, ~p"/projects/#{project.id}/w/new"),
               "expected #{role} to reach the new workflow editor"
      end
    end

    test "does not block a viewer from opening an existing workflow", %{
      conn: conn,
      user: user
    } do
      # The gate is on creation only - viewers keep their read-only access to
      # workflows that already exist.
      project =
        insert(:project, project_users: [%{user_id: user.id, role: :viewer}])

      workflow = insert(:workflow, project: project)

      assert {:ok, _view, _html} =
               live(conn, ~p"/projects/#{project.id}/w/#{workflow.id}")
    end
  end
end
