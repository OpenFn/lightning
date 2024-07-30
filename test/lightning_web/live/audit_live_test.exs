defmodule LightningWeb.AuditLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.CredentialsFixtures

  alias LightningWeb.LiveHelpers

  describe "Index as a regular user" do
    setup :register_and_log_in_user

    test "cannot access the audit trail", %{conn: conn} do
      {:ok, _index_live, html} =
        live(conn, ~p"/settings/audit") |> follow_redirect(conn, "/projects")

      assert html =~ "Sorry, you don&#39;t have access to that."
    end
  end

  describe "Index as a superuser" do
    setup :register_and_log_in_superuser
    setup :create_project_for_current_user

    test "lists all audit entries", %{conn: conn, user: user} do
      # Generate an audit event on creation.
      credential =
        credential_fixture(user_id: user.id, body: %{"my-secret" => "value"})

      # Add another audit event, but this time for a user that doesn't exist to
      # simulate an event from a user that has since been deleted.
      deleted_user_id = "655993ca-4828-496c-8ff9-e742b175e462"

      {:ok, _audit} =
        Lightning.Credentials.Audit.event(
          "deleted",
          credential.id,
          deleted_user_id
        )
        |> Lightning.Credentials.Audit.save()

      {:ok, _index_live, html} =
        live(conn, Routes.audit_index_path(conn, :index))

      assert html =~ "Audit"
      # Assert that the table works for users that still exist.
      assert html =~ user.first_name
      assert html =~ user.email
      assert html =~ LiveHelpers.display_short_uuid(credential.id)
      assert html =~ "created"
      assert html =~ "No changes"
      refute html =~ "nil"

      # Assert that the table works for users that have been deleted.
      assert html =~ "created"
      assert html =~ "(User deleted)"
      assert html =~ LiveHelpers.display_short_uuid(deleted_user_id)
    end
  end
end
