defmodule LightningWeb.MaintenanceLive.IndexTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

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
  end
end
