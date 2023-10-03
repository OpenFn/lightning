defmodule LightningWeb.LiveDashboardTest do
  use LightningWeb.ConnCase, async: true

  describe "the user is not logged-in" do
    test "redirects the user to the sign-in page", %{conn: conn} do
      conn = conn |> get(~p"/dashboard")

      assert redirected_to(conn) == Routes.user_session_path(conn, :new)
    end
  end

  describe "the user is not a superuser" do
    setup :register_and_log_in_user

    test "routes the user to '/'", %{conn: conn} do
      conn = conn |> get(~p"/dashboard")

      assert redirected_to(conn) == Routes.dashboard_index_path(conn, :index)
    end

    test "shows an error message", %{conn: conn} do
      conn = conn |> get(~p"/dashboard")

      conn = get(conn, Routes.dashboard_index_path(conn, :index))

      assert html_response(conn, 200) =~
               "Sorry, you don&#39;t have access to that"
    end
  end

  describe "the user is a superuser" do
    setup :register_and_log_in_superuser

    test "routes the user to the live dashboard", %{conn: conn} do
      conn = conn |> get(~p"/dashboard")

      assert redirected_to(conn) == ~p"/dashboard/home"
    end
  end
end
