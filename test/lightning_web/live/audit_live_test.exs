defmodule LightningWeb.AuditLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.CredentialsFixtures
  import Lightning.Factories

  alias Lightning.Repo
  alias LightningWeb.LiveHelpers

  # The page is drawn by React from data-props.
  defp props(live), do: page_props(live, "#admin-audit-page")
  defp events(live), do: props(live)["events"]

  defp event_for(live, item_id),
    do: Enum.find(events(live), &(&1["itemId"] == item_id))

  describe "Index as a regular user" do
    setup :register_and_log_in_user

    test "cannot access the audit trail", %{conn: conn} do
      {:ok, conn} =
        live(conn, ~p"/settings/audit", on_error: :raise)
        |> follow_redirect(conn, "/projects")

      assert conn.resp_body =~ "Sorry, you don&#39;t have access to that."
    end
  end

  describe "Index as a superuser" do
    setup :register_and_log_in_superuser
    setup :create_project_for_current_user

    test "lists all audit entries", %{conn: conn, user: user} do
      # Generate an audit event on creation.
      credential =
        credential_fixture(user_id: user.id, schema: "raw")
        |> with_body(%{name: "main", body: %{"my-secret" => "value"}})

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

      {:ok, live, html} = live(conn, ~p"/settings/audit", on_error: :raise)

      assert html =~ "Audit"

      for_credential =
        Enum.filter(events(live), &(&1["itemId"] == credential.id))

      assert length(for_credential) == 2
      created = Enum.find(for_credential, &(&1["event"] == "created"))
      deleted = Enum.find(for_credential, &(&1["event"] == "deleted"))

      # The table works for users that still exist.
      assert %{
               "event" => "created",
               "itemType" => "credential",
               "actorId" => actor_id,
               "actorLabel" => label,
               "actorIdentifier" => identifier,
               "changes" => %{"before" => nil, "after" => after_values},
               "credentialBodies" => nil
             } = created

      assert actor_id == user.id
      assert label == "#{user.first_name} #{user.last_name}"
      assert identifier == user.email
      assert %{"name" => "some name", "schema" => "raw"} = after_values

      # And for users that have been deleted.
      assert %{
               "event" => "deleted",
               "actorLabel" => "(User deleted)",
               "actorIdentifier" => nil,
               "actorId" => deleted_id
             } = deleted

      assert LiveHelpers.display_short_uuid(deleted_id) ==
               LiveHelpers.display_short_uuid(user_to_be_deleted.id)

      # The secret itself never reaches the page.
      refute html =~ "my-secret"
      refute html =~ "value\""
    end

    test "pages ten events at a time from ?page", %{conn: conn, user: user} do
      for i <- 1..25 do
        insert(:audit,
          actor_type: :user,
          actor_id: user.id,
          inserted_at: DateTime.add(DateTime.utc_now(), -i, :second)
        )
      end

      {:ok, live, _html} = live(conn, ~p"/settings/audit", on_error: :raise)

      assert %{"pageNumber" => 1, "pageSize" => 10, "totalEntries" => 25} =
               props(live)

      assert length(events(live)) == 10

      render_patch(live, ~p"/settings/audit?page=3")

      assert %{"pageNumber" => 3, "totalEntries" => 25} = props(live)
      assert length(events(live)) == 5
    end

    test "sends changes with either key kind, scalars as they are", %{
      conn: conn,
      user: user
    } do
      strings =
        insert(:audit,
          actor_type: :user,
          actor_id: user.id,
          changes: %{
            before: %{"period" => 30, "name" => "old"},
            after: %{"period" => 7, "name" => "new", "enabled" => true}
          }
        )

      atoms =
        insert(:audit,
          actor_type: :user,
          actor_id: user.id,
          changes: %{before: %{foo: "f1"}, after: %{foo: "f2", nested: %{a: 1}}}
        )

      created =
        insert(:audit,
          actor_type: :user,
          actor_id: user.id,
          changes: %{before: nil, after: %{"email" => "amara@example.org"}}
        )

      {:ok, live, _html} = live(conn, ~p"/settings/audit", on_error: :raise)

      assert %{
               "before" => %{"period" => 30, "name" => "old"},
               "after" => %{"period" => 7, "name" => "new", "enabled" => true}
             } = event_for(live, strings.item_id)["changes"]

      # Nested values go as JSON text, since the page prints text.
      assert %{
               "before" => %{"foo" => "f1"},
               "after" => %{"foo" => "f2", "nested" => "{\"a\":1}"}
             } = event_for(live, atoms.item_id)["changes"]

      assert %{"before" => nil, "after" => %{"email" => "amara@example.org"}} =
               event_for(live, created.item_id)["changes"]
    end

    test "sends encrypted credential bodies from the metadata", %{
      conn: conn,
      user: user
    } do
      with_bodies =
        insert(:audit,
          actor_type: :user,
          actor_id: user.id,
          changes: %{before: nil, after: nil},
          metadata: %{
            "credential_bodies" => %{
              "body:staging" => "abc==",
              "body:production" => "xyz=="
            }
          }
        )

      without =
        insert(:audit,
          actor_type: :user,
          actor_id: user.id,
          metadata: %{"credential_bodies" => %{}}
        )

      {:ok, live, _html} = live(conn, ~p"/settings/audit", on_error: :raise)

      assert event_for(live, with_bodies.item_id)["credentialBodies"] == %{
               "body:staging" => "abc==",
               "body:production" => "xyz=="
             }

      assert event_for(live, without.item_id)["credentialBodies"] == nil
    end

    test "labels a service account by its id", %{conn: conn} do
      audit =
        insert(:audit,
          actor_type: :service_account,
          actor_id: Ecto.UUID.generate(),
          metadata: %{"service_account_id" => "key-1234"}
        )

      {:ok, live, _html} = live(conn, ~p"/settings/audit", on_error: :raise)

      assert %{
               "actorLabel" => "Service account",
               "actorIdentifier" => "key-1234"
             } = event_for(live, audit.item_id)
    end
  end
end
