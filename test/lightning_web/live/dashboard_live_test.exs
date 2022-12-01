defmodule LightningWeb.DashboardLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "Index" do
    setup :register_and_log_in_user

    test "User is assigned no project", %{
      conn: conn
    } do
      {:ok, _view, html} = live(conn, Routes.dashboard_index_path(conn, :index))

      assert html =~
               "No projects found. If this seems odd, contact your instance administrator."

      assert html =~ "User Profile"
      assert html =~ "Credentials"
    end

    test "Side menu has credentials and user profile navigation", %{
      conn: conn
    } do
      {:ok, index_live, _html} =
        live(conn, Routes.dashboard_index_path(conn, :index))

      assert {:ok, profile_live, _html} =
               index_live
               |> element("nav#side-menu a", "User Profile")
               |> render_click()
               |> follow_redirect(
                 conn,
                 Routes.profile_edit_path(conn, :edit)
               )

      assert profile_live
             |> element("nav#side-menu a", "Credentials")
             |> render_click()
             |> follow_redirect(
               conn,
               Routes.credential_index_path(conn, :index)
             )
    end
  end

  describe "Index redirects to show" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    test "User is assigned a project, should redirect", %{
      conn: conn,
      project: project
    } do
      {:ok, _view, html} =
        live(conn, Routes.dashboard_index_path(conn, :index))
        |> follow_redirect(
          conn,
          Routes.project_process_path(conn, :index, project.id)
        )

      assert html =~ "Create a workflow"
    end
  end
end
