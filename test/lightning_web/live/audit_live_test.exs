defmodule LightningWeb.AuditLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  describe "Index as a regular user" do
    setup :register_and_log_in_user

    test "cannot access the audit trail", %{conn: conn} do
      {:ok, _index_live, html} =
        live(conn, ~p"/settings/audit") |> follow_redirect(conn, "/")

      assert html =~ "Sorry, you don&#39;t have access to that."
    end
  end

  describe "Index as a superuser" do
    setup [:register_and_log_in_superuser]

    test "lists all audit entries", %{conn: conn} do
      {:ok, _index_live, html} =
        live(conn, Routes.audit_index_path(conn, :index))

      assert html =~ "Audit"
    end
  end
end
