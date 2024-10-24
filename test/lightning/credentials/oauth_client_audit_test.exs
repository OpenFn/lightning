defmodule Lightning.Credentials.OauthClientAuditTest do
  use Lightning.DataCase, async: true

  alias Lightning.Credentials.OauthClient
  alias Lightning.Credentials.OauthClientAudit

  describe ".user_initiated_event/3" do
    test "returns audit changeset if user association is loaded" do
      %{id: client_id, user_id: user_id} =
        client =
        insert(
          :oauth_client,
          token_endpoint: "https://example.com/token"
        )
        |> Repo.preload(:user)

      changes =
        client
        |> OauthClient.changeset(%{token_endpoint: "https://example.com/token2"})

      audit_changeset =
        OauthClientAudit.user_initiated_event("updated", client, changes)

      assert %{
               changes: %{
                 event: "updated",
                 item_type: "oauth_client",
                 item_id: ^client_id,
                 actor_id: ^user_id,
                 actor_type: :user,
                 changes: %{
                   changes: %{
                     before: %{
                       token_endpoint: "https://example.com/token"
                     },
                     after: %{
                       token_endpoint: "https://example.com/token2"
                     }
                   }
                 }
               }
             } = audit_changeset
    end

    test "returns audit changeset if user association is not loaded" do
      %{id: client_id, user_id: user_id} =
        insert(
          :oauth_client,
          token_endpoint: "https://example.com/token"
        )

      client_without_user = Repo.get(OauthClient, client_id)

      changes =
        client_without_user
        |> OauthClient.changeset(%{token_endpoint: "https://example.com/token2"})

      audit_changeset =
        "updated"
        |> OauthClientAudit.user_initiated_event(client_without_user, changes)

      assert %{
               changes: %{
                 event: "updated",
                 item_type: "oauth_client",
                 item_id: ^client_id,
                 actor_id: ^user_id,
                 actor_type: :user,
                 changes: %{
                   changes: %{
                     before: %{
                       token_endpoint: "https://example.com/token"
                     },
                     after: %{
                       token_endpoint: "https://example.com/token2"
                     }
                   }
                 }
               }
             } = audit_changeset
    end

    test "returns audit changeset if no changes are provided" do
      %{id: client_id, user_id: user_id} =
        client =
        insert(
          :oauth_client,
          token_endpoint: "https://example.com/token"
        )

      audit_changeset = OauthClientAudit.user_initiated_event("deleted", client)

      assert %{
               changes: %{
                 event: "deleted",
                 item_type: "oauth_client",
                 item_id: ^client_id,
                 actor_id: ^user_id,
                 actor_type: :user,
                 changes: %{
                   changes: %{}
                 }
               }
             } = audit_changeset
    end
  end
end
