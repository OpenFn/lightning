defmodule Lightning.Credentials.AuditTest do
  use Lightning.DataCase, async: true

  alias Lightning.Credentials.{Audit, Credential}

  import Lightning.{AccountsFixtures, CredentialsFixtures}

  describe "event/4" do
    test "generates 'created' audit trail entries" do
      user = user_fixture()

      credential =
        credential_fixture(user_id: user.id)
        |> with_body(%{name: "main", body: %{"my-secret" => "value"}})

      {:ok, audit} =
        Audit.event("created", credential.id, user)
        |> Audit.save()

      assert audit.item_type == "credential"
      assert audit.item_id == credential.id
      assert %{before: nil, after: nil} = audit.changes
      assert audit.event == "created"
      assert audit.actor_id == user.id
      assert audit.actor_type == :user
    end

    test "generates 'updated' audit trail entries with environment bodies" do
      user = user_fixture()

      credential =
        credential_fixture(user_id: user.id)
        |> with_body(%{name: "main", body: %{"old-secret" => "old"}})

      changeset = Credential.changeset(credential, %{name: "Updated Name"})

      metadata = %{
        credential_bodies: %{
          "body:main" =>
            Base.encode64(
              elem(Lightning.Encrypted.Map.dump(%{"my-secret" => "value"}), 1)
            )
        },
        environments: ["main"]
      }

      {:ok, audit} =
        Audit.event("updated", credential.id, user, changeset, metadata)
        |> Audit.save()

      assert audit.item_type == "credential"
      assert audit.item_id == credential.id

      # Check that environment bodies are encrypted in metadata
      assert audit.metadata.environments == ["main"]
      assert audit.metadata.credential_bodies["body:main"] =~ "AQpBRVMuR0NNLlYx"

      assert audit.event == "updated"
      assert audit.actor_id == user.id
      assert audit.actor_type == :user
    end

    test "generates 'deleted' audit trail entries" do
      user = user_fixture()

      credential =
        credential_fixture(user_id: user.id)
        |> with_body(%{name: "main", body: %{"my-secret" => "value"}})

      {:ok, audit} =
        Audit.event("deleted", credential.id, user)
        |> Audit.save()

      assert audit.item_type == "credential"
      assert audit.item_id == credential.id

      assert audit.changes == %Lightning.Auditing.Audit.Changes{
               before: nil,
               after: nil
             }

      assert audit.event == "deleted"
      assert audit.actor_id == user.id
      assert audit.actor_type == :user
    end
  end

  describe ".user_initiated_event" do
    test "generates changeset for event with environment bodies in metadata" do
      %{id: user_id} = user_fixture()

      %{id: credential_id} =
        credential =
        credential_fixture(user_id: user_id)
        |> with_body(%{name: "main", body: %{"old" => "value"}})
        |> Repo.preload(:user)

      changeset = Credential.changeset(credential, %{name: "Updated"})

      env_bodies = [
        {"main", %{"my-secret" => "value"}},
        {"production", %{"prod-secret" => "prod-value"}}
      ]

      audit_changeset =
        Audit.user_initiated_event("updated", credential, changeset, env_bodies)

      assert %{
               changes: %{
                 event: "updated",
                 item_id: ^credential_id,
                 item_type: "credential",
                 actor_id: ^user_id,
                 actor_type: :user,
                 metadata: metadata
               }
             } = audit_changeset

      # Check that environment bodies are encrypted in metadata
      assert metadata.environments == ["main", "production"]
      assert metadata.credential_bodies["body:main"] =~ "AQpBRVMuR0NNLlYx"
      assert metadata.credential_bodies["body:production"] =~ "AQpBRVMuR0NNLlYx"
    end

    test "generates changeset for event without environment bodies" do
      %{id: user_id} = user_fixture()

      %{id: credential_id} =
        credential =
        credential_fixture(user_id: user_id)
        |> with_body(%{name: "main", body: %{}})
        |> Repo.preload(:user)

      changeset = Credential.changeset(credential, %{name: "New Name"})

      audit_changeset =
        Audit.user_initiated_event("updated", credential, changeset)

      assert %{
               changes: %{
                 event: "updated",
                 item_id: ^credential_id,
                 item_type: "credential",
                 actor_id: ^user_id,
                 actor_type: :user
               }
             } = audit_changeset

      # No metadata when no environment bodies provided (empty list defaults to empty map)
      metadata = audit_changeset.changes[:metadata] || %{}
      assert metadata == %{}
    end

    test "generates changeset for deleted event" do
      %{id: user_id} = user_fixture()

      %{id: credential_id} =
        credential =
        credential_fixture(user_id: user_id)
        |> with_body(%{name: "main", body: %{}})
        |> Repo.preload(:user)

      audit_changeset = Audit.user_initiated_event("deleted", credential)

      assert %{
               changes: %{
                 event: "deleted",
                 item_id: ^credential_id,
                 item_type: "credential",
                 actor_id: ^user_id,
                 actor_type: :user,
                 changes: %{
                   changes: %{}
                 }
               }
             } = audit_changeset
    end

    test "generates changeset for created event with multiple environments" do
      %{id: user_id} = user_fixture()

      %{id: credential_id} =
        credential =
        credential_fixture(user_id: user_id)
        |> Repo.preload(:user)

      env_bodies = [
        {"main", %{"key" => "main-value"}},
        {"staging", %{"key" => "staging-value"}},
        {"production", %{"key" => "prod-value"}}
      ]

      # Need a changeset with actual changes for audit to work
      changeset = Credential.changeset(credential, %{name: "New Credential"})

      audit_changeset =
        Audit.user_initiated_event("created", credential, changeset, env_bodies)

      assert %{
               changes: %{
                 event: "created",
                 item_id: ^credential_id,
                 item_type: "credential",
                 actor_id: ^user_id,
                 actor_type: :user,
                 metadata: metadata
               }
             } = audit_changeset

      assert metadata.environments == ["main", "staging", "production"]
      assert map_size(metadata.credential_bodies) == 3

      # All bodies should be encrypted
      Enum.each(["main", "staging", "production"], fn env ->
        assert metadata.credential_bodies["body:#{env}"] =~ "AQpBRVMuR0NNLlYx"
      end)
    end
  end

  describe ".oauth_token_refreshed_event" do
    test "creates audit event with refresh metadata" do
      user = user_fixture()

      credential =
        credential_fixture(user_id: user.id, schema: "oauth")
        |> Repo.preload(:user)

      metadata = %{
        client_id: Ecto.UUID.generate(),
        scopes: ["read", "write"],
        expires_in: 3600,
        token_type: "Bearer",
        environment: "production"
      }

      audit_changeset =
        Audit.oauth_token_refreshed_event(credential, metadata)

      assert %{
               changes: %{
                 event: "token_refreshed",
                 item_id: item_id,
                 item_type: "credential",
                 actor_id: actor_id,
                 metadata: audit_metadata
               }
             } = audit_changeset

      assert item_id == credential.id
      assert actor_id == user.id
      assert audit_metadata.client_id == metadata.client_id
      assert audit_metadata.scopes == ["read", "write"]
      assert audit_metadata.environment == "production"
      assert %DateTime{} = audit_metadata.refreshed_at
    end
  end

  describe ".oauth_token_refresh_failed_event" do
    test "creates audit event with error details" do
      user = user_fixture()

      credential =
        credential_fixture(user_id: user.id, schema: "oauth")
        |> Repo.preload(:user)

      error_details = %{
        status: 401,
        error_type: "reauthorization_required",
        client_id: Ecto.UUID.generate(),
        environment: "production"
      }

      audit_changeset =
        Audit.oauth_token_refresh_failed_event(credential, error_details)

      assert %{
               changes: %{
                 event: "token_refresh_failed",
                 item_id: item_id,
                 metadata: metadata
               }
             } = audit_changeset

      assert item_id == credential.id
      assert metadata.status == 401
      assert metadata.error_type == "reauthorization_required"
      assert metadata.environment == "production"
      assert %DateTime{} = metadata.failed_at
    end
  end

  describe ".oauth_token_revoked_event" do
    test "creates audit event with revocation metadata" do
      user = user_fixture()

      credential =
        credential_fixture(user_id: user.id, schema: "oauth")
        |> Repo.preload(:user)

      metadata = %{
        client_id: Ecto.UUID.generate(),
        revocation_endpoint: "https://oauth.provider.com/revoke",
        success: true,
        environment: "production"
      }

      audit_changeset =
        Audit.oauth_token_revoked_event(credential, metadata)

      assert %{
               changes: %{
                 event: "token_revoked",
                 item_id: item_id,
                 metadata: audit_metadata
               }
             } = audit_changeset

      assert item_id == credential.id
      assert audit_metadata.success == true
      assert audit_metadata.environment == "production"
      assert %DateTime{} = audit_metadata.revoked_at
    end
  end
end
