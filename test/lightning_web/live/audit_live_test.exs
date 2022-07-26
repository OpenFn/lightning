defmodule LightningWeb.AuditLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "Index as a regular user" do
    setup :register_and_log_in_user

    test "cannot access the users page", %{conn: conn} do
      {:ok, _index_live, html} =
        live(conn, Routes.audit_index_path(conn, :index))
        |> follow_redirect(conn, "/")

      assert html =~ "You can&#39;t access that page"
    end
  end

  describe "Index" do
    setup [:register_and_log_in_superuser]

    test "lists all audit entries", %{conn: conn} do
      {:ok, _index_live, html} =
        live(conn, Routes.audit_index_path(conn, :index))

      assert html =~ "Audit"
    end
  end
end
