defmodule LightningWeb.AuditLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.CredentialsFixtures
  import Lightning.Factories

  alias Lightning.Repo
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

      # Add another audit event, but this time for a user that will be deleted
      # before the listing
      user_to_be_deleted = insert(:user)

      {:ok, _audit} =
        Lightning.Credentials.Audit.event(
          "deleted",
          credential.id,
          user_to_be_deleted
        )
        |> Lightning.Credentials.Audit.save()

      Repo.delete!(user_to_be_deleted)

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
      assert html =~ LiveHelpers.display_short_uuid(user_to_be_deleted.id)
    end
  end
end
