defmodule LightningWeb.MaintenanceLive.IndexTest do
  # async: false because the icon-refresh test stubs Lightning.Adaptors.StrategyMock
  # globally, which the singleton Scheduler GenServer (not in the test pid's
  # caller chain) needs to see.
  use LightningWeb.ConnCase, async: false

  import Mox
  import Phoenix.LiveViewTest

  setup :set_mox_global

  describe "Index as a regular user" do
    setup :register_and_log_in_user

    test "cannot access the maintenance page", %{conn: conn} do
      {:ok, _live, html} =
        live(conn, ~p"/settings/maintenance", on_error: :raise)
        |> follow_redirect(conn, "/projects")

      assert html =~ "Sorry, you don&#39;t have access to that."
    end
  end

  describe "Index as a superuser" do
    setup :register_and_log_in_superuser

    test "renders the Refresh Adaptor Registry card", %{conn: conn} do
      {:ok, _live, html} =
        live(conn, ~p"/settings/maintenance", on_error: :raise)

      assert html =~ "Maintenance"
      assert html =~ "Refresh Adaptor Registry"
      assert html =~ "Re-fetch the list of available adaptors"
      assert html =~ "Run"
    end

    test "clicking Run flashes that the refresh was queued", %{conn: conn} do
      {:ok, live, _html} =
        live(conn, ~p"/settings/maintenance", on_error: :raise)

      live
      |> element("#refresh-adaptors-button")
      |> render_click()

      assert has_element?(
               live,
               "p[role=alert][phx-value-key=info]",
               "Adaptor refresh queued."
             )
    end

    test "renders the Refresh Adaptor Icons card", %{conn: conn} do
      {:ok, live, html} =
        live(conn, ~p"/settings/maintenance", on_error: :raise)

      assert html =~ "Refresh Adaptor Icons"
      assert has_element?(live, "#refresh-icons-button")
    end

    test "clicking the icons button reports the refresh result", %{conn: conn} do
      stub(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
        {:ok, %{}}
      end)

      {:ok, live, _html} =
        live(conn, ~p"/settings/maintenance", on_error: :raise)

      live
      |> element("#refresh-icons-button")
      |> render_click()

      assert has_element?(
               live,
               "p[role=alert][phx-value-key=info]",
               "Icon refresh complete"
             )
    end
  end
end
