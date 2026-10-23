defmodule LightningWeb.MaintenanceLive.IndexTest do
  # async: false because the icon-refresh test stubs Lightning.Adaptors.StrategyMock
  # globally, which the singleton Scheduler GenServer (not in the test pid's
  # caller chain) needs to see.
  use LightningWeb.ConnCase, async: false

  import Mox
  import Phoenix.LiveViewTest

  setup :set_mox_global

  # The page is drawn by React from data-props (none here: it is two
  # actions). Its cards, texts and buttons are tested in the design system's
  # AdminMaintenancePage.test.tsx; the events it sends in
  # assets/test/design-system/AdminMaintenancePage.test.tsx.
  @page "#admin-maintenance-page"

  defp run(view, action), do: push_page_event(view, @page, action)

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

    test "renders the maintenance page for the design system", %{conn: conn} do
      {:ok, live, html} =
        live(conn, ~p"/settings/maintenance", on_error: :raise)

      assert html =~ "Maintenance"
      assert page_props(live, @page) == %{}
    end

    test "refresh_adaptors flashes that the refresh was queued", %{conn: conn} do
      {:ok, live, _html} =
        live(conn, ~p"/settings/maintenance", on_error: :raise)

      run(live, "refresh_adaptors")

      assert_reply(live, %{})

      assert has_element?(
               live,
               "#flash-bridge[data-info='Adaptor refresh queued.']"
             )
    end

    test "refresh_icons starts the refresh and reports the result asynchronously",
         %{conn: conn} do
      stub(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
        {:ok, %{}}
      end)

      {:ok, live, _html} =
        live(conn, ~p"/settings/maintenance", on_error: :raise)

      assert run(live, "refresh_icons") =~ "Icon refresh started."

      render_async(live)

      assert has_element?(
               live,
               "#flash-bridge[data-info^='Icon refresh complete']"
             )
    end

    test "refresh_icons reports a failed refresh", %{conn: conn} do
      stub(Lightning.Adaptors.StrategyMock, :fetch_icons, fn _opts ->
        {:error, :boom}
      end)

      {:ok, live, _html} =
        live(conn, ~p"/settings/maintenance", on_error: :raise)

      run(live, "refresh_icons")

      render_async(live)

      assert has_element?(
               live,
               "#flash-bridge[data-error^='Icon refresh failed']"
             )
    end
  end
end
