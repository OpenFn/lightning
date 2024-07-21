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
      {:ok, _view, html} = live(conn, ~p"/")

      assert html =~ "No projects found. Create a new one."

      assert html =~ "User Profile"
      assert html =~ "Credentials"
    end

    test "Side menu has credentials and user profile navigation", %{
      conn: conn
    } do
      {:ok, index_live, _html} = live(conn, ~p"/")

      assert {:ok, profile_live, _html} =
               index_live
               |> element("nav#side-menu a", "User Profile")
               |> render_click()
               |> follow_redirect(conn, ~p"/profile")

      assert profile_live
             |> element("nav#side-menu a", "Credentials")
             |> render_click()
             |> follow_redirect(conn, ~p"/credentials")
    end
  end
end
