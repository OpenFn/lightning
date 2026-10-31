defmodule LightningWeb.LiveDashboardTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

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

    test "connects to the dashboard LiveView", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/dashboard/home")

      assert html =~ "Home"
    end
  end

  describe "mounting over the socket" do
    # A client whose transport is hung up reconnects straight to a mount, which
    # the `:require_authenticated_user` and `:require_superuser` plugs never see,
    # so this route's hooks are its only auth check on that path. What the hooks
    # themselves do is pinned in init_assigns_test.exs and live/hooks_test.exs.
    test "declares the hooks that authorise a reconnecting client" do
      %{
        phoenix_live_view: {_view, _action, _opts, %{extra: %{on_mount: hooks}}}
      } =
        Phoenix.Router.route_info(
          LightningWeb.Router,
          "GET",
          "/dashboard",
          "localhost"
        )

      assert Enum.map(hooks, & &1.id) == [
               {LightningWeb.InitAssigns, :default},
               {LightningWeb.Hooks, :ensure_admin}
             ]
    end
  end
end
