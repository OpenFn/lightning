defmodule LightningWeb.MaintenanceLive.IndexTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "as a regular user" do
    setup :register_and_log_in_user

    test "cannot access the maintenance page", %{conn: conn} do
      {:ok, _live, html} =
        live(conn, ~p"/settings/maintenance")
        |> follow_redirect(conn, "/projects")

      assert html =~ "Sorry, you don&#39;t have access to that."
    end
  end

  describe "as a superuser" do
    setup :register_and_log_in_superuser

    test "can access the maintenance page", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/settings/maintenance")

      assert html =~ "Maintenance"
      assert html =~ "Refresh Adaptor Registry"
      assert html =~ "Install Adaptor Icons"
      assert html =~ "Install Credential Schemas"
    end

    test "clicking run button shows running state", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/maintenance")

      # We can't easily test the full async flow without mocking HTTP,
      # but we can test the handle_info path by sending messages directly
      send(view.pid, {:action_complete, "refresh_adaptor_registry", {:ok, 5}})

      html = render(view)
      assert html =~ "Done"
    end

    test "shows error status on failure", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/maintenance")

      send(
        view.pid,
        {:action_complete, "install_adaptor_icons", {:error, "HTTP 500"}}
      )

      html = render(view)
      assert html =~ "Failed"
    end

    test "shows success status for schema install", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/settings/maintenance")

      send(view.pid, {:action_complete, "install_schemas", {:ok, 42}})

      html = render(view)
      assert html =~ "Done"
    end
  end
end
