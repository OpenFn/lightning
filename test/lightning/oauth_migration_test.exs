defmodule Lightning.Credentials.OauthMigrationTest do
  use Lightning.DataCase, async: true

  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.OauthToken
  alias Lightning.Credentials.OauthMigration
  alias Lightning.Repo

  import Lightning.Factories

  describe "run/0" do
    test "migrates oauth credentials to oauth tokens" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      credential =
        insert(:credential,
          schema: "oauth",
          user: user,
          oauth_client: oauth_client,
          body: %{
            "access_token" => "test_access_token",
            "refresh_token" => "test_refresh_token",
            "expires_at" => 3600,
            "scope" => "read write"
          },
          oauth_token_id: nil
        )

      results = OauthMigration.run()

      assert results.tokens_created > 0
      assert results.credentials_updated > 0

      updated_credential = Repo.get!(Credential, credential.id)

      assert updated_credential.oauth_token_id != nil

      token = Repo.get!(OauthToken, updated_credential.oauth_token_id)

      assert token.body["access_token"] == "test_access_token"
      assert token.body["refresh_token"] == "test_refresh_token"
      assert token.body["expires_at"] == 3600
      assert token.scopes == ["read", "write"]
    end

    test "preserves apiVersion when migrating credentials" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      credential =
        insert(:credential,
          schema: "oauth",
          user: user,
          oauth_client: oauth_client,
          body: %{
            "access_token" => "test_access_token",
            "refresh_token" => "test_refresh_token",
            "expires_at" => 3600,
            "scope" => "read write",
            "apiVersion" => "v52.0"
          },
          oauth_token_id: nil
        )

      OauthMigration.run()

      updated_credential = Repo.get!(Credential, credential.id)
      assert updated_credential.body["apiVersion"] == "v52.0"

      token = Repo.get!(OauthToken, updated_credential.oauth_token_id)
      assert token.body["access_token"] == "test_access_token"
      assert token.body["refresh_token"] == "test_refresh_token"
    end

    test "reuses existing token with matching scopes" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      existing_token =
        insert(:oauth_token,
          user: user,
          oauth_client: oauth_client,
          scope: ["read", "write", "profile"],
          body: %{
            "access_token" => "existing_token",
            "refresh_token" => "existing_refresh",
            "expires_at" => 3600,
            "scope" => "read write profile"
          }
        )

      credential =
        insert(:credential,
          schema: "oauth",
          user: user,
          oauth_client: oauth_client,
          body: %{
            "access_token" => "test_access_token",
            "refresh_token" => "test_refresh_token",
            "expires_at" => 3600,
            "scope" => "read write"
          },
          oauth_token_id: nil
        )

      results = OauthMigration.run()

      assert results.credentials_updated > 0

      updated_credential = Repo.get!(Credential, credential.id)
      assert updated_credential.oauth_token_id == existing_token.id
    end

    test "handles credentials with missing scope" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      credential =
        insert(:credential,
          schema: "oauth",
          user: user,
          oauth_client: oauth_client,
          body: %{
            "access_token" => "test_access_token",
            "refresh_token" => "test_refresh_token",
            "expires_at" => 3600
          },
          oauth_token_id: nil
        )

      results = OauthMigration.run()

      assert results.credentials_updated > 0

      updated_credential = Repo.get!(Credential, credential.id)
      assert updated_credential.oauth_token_id != nil

      token = Repo.get!(OauthToken, updated_credential.oauth_token_id)
      assert token.scopes == []
    end

    test "does not process already migrated credentials" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      token =
        insert(:oauth_token,
          user: user,
          oauth_client: oauth_client,
          scope: ["read", "write"],
          body: %{
            "access_token" => "existing_token",
            "refresh_token" => "existing_refresh",
            "expires_at" => 3600,
            "scope" => "read write"
          }
        )

      credential =
        insert(:credential,
          schema: "oauth",
          user: user,
          oauth_client: oauth_client,
          body: %{"apiVersion" => "v52.0"},
          oauth_token_id: token.id
        )

      unmigrated =
        insert(:credential,
          schema: "oauth",
          user: user,
          oauth_client: oauth_client,
          body: %{
            "access_token" => "unmigrated_token",
            "refresh_token" => "unmigrated_refresh",
            "expires_at" => 3600,
            "scope" => "execute"
          },
          oauth_token_id: nil
        )

      results = OauthMigration.run()

      assert results.credentials_updated == 1

      unchanged = Repo.get!(Credential, credential.id)
      assert unchanged.oauth_token_id == token.id
      assert unchanged.body == %{"apiVersion" => "v52.0"}

      migrated = Repo.get!(Credential, unmigrated.id)
      assert migrated.oauth_token_id != nil
      refute migrated.oauth_token_id == token.id
    end

    test "only processes oauth schema credentials" do
      user = insert(:user)

      credential =
        insert(:credential,
          schema: "postgresql",
          user: user,
          body: %{
            "user" => "postgres",
            "password" => "postgres",
            "host" => "localhost",
            "port" => 5432,
            "database" => "test"
          },
          oauth_token_id: nil
        )

      oauth_credential =
        insert(:credential,
          schema: "oauth",
          user: user,
          oauth_client: insert(:oauth_client),
          body: %{
            "access_token" => "test_access_token",
            "refresh_token" => "test_refresh_token",
            "expires_at" => 3600,
            "scope" => "read write"
          },
          oauth_token_id: nil
        )

      results = OauthMigration.run()

      assert results.credentials_updated == 1

      unchanged = Repo.get!(Credential, credential.id)
      assert unchanged.oauth_token_id == nil

      assert unchanged.body == %{
               "user" => "postgres",
               "password" => "postgres",
               "host" => "localhost",
               "port" => 5432,
               "database" => "test"
             }

      updated = Repo.get!(Credential, oauth_credential.id)
      assert updated.oauth_token_id != nil
    end

    test "skips credentials with nil oauth_client_id" do
      user = insert(:user)

      credential =
        insert(:credential,
          schema: "oauth",
          user: user,
          oauth_client_id: nil,
          body: %{
            "access_token" => "test_access_token",
            "refresh_token" => "test_refresh_token",
            "expires_at" => 3600,
            "scope" => "read write"
          },
          oauth_token_id: nil
        )

      valid_credential =
        insert(:credential,
          schema: "oauth",
          user: user,
          oauth_client: insert(:oauth_client),
          body: %{
            "access_token" => "valid_token",
            "refresh_token" => "valid_refresh",
            "expires_at" => 3600,
            "scope" => "read write"
          },
          oauth_token_id: nil
        )

      results = OauthMigration.run()

      assert results.credentials_updated == 1
      assert results.tokens_created == 1

      unchanged_credential = Repo.get!(Credential, credential.id)
      assert unchanged_credential.oauth_token_id == nil

      updated_valid = Repo.get!(Credential, valid_credential.id)
      assert updated_valid.oauth_token_id != nil
    end

    test "migration runs correctly when no credentials need to be migrated" do
      results = OauthMigration.run()

      assert results.tokens_created == 0
      assert results.credentials_updated == 0
    end
  end

  describe "error handling" do
    test "handles credentials with nil body" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      credential =
        insert(:credential,
          schema: "oauth",
          user: user,
          oauth_client: oauth_client,
          body: nil,
          oauth_token_id: nil
        )

      results = OauthMigration.run()

      assert results.credentials_updated == 0

      unchanged = Repo.get!(Credential, credential.id)
      assert unchanged.oauth_token_id == nil
      assert unchanged.body == nil
    end

    test "handles credentials with invalid body gracefully" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      valid_credential =
        insert(:credential,
          schema: "oauth",
          user: user,
          oauth_client: oauth_client,
          body: %{
            "access_token" => "test_access_token",
            "refresh_token" => "test_refresh_token",
            "expires_at" => 3600,
            "scope" => "read write"
          },
          oauth_token_id: nil
        )

      bad_credential =
        insert(:credential,
          schema: "oauth",
          user: user,
          oauth_client: oauth_client,
          body: %{
            "access_token" => "bad_token",
            "expires_at" => 3600,
            "scope" => "read write"
          },
          oauth_token_id: nil
        )

      results = OauthMigration.run()

      assert results.credentials_updated >= 1

      updated_valid = Repo.get!(Credential, valid_credential.id)
      assert updated_valid.oauth_token_id != nil

      bad_after_migration = Repo.get!(Credential, bad_credential.id)

      assert is_map(bad_after_migration)
    end
  end

  describe "comprehensive migration" do
    test "processes multiple credentials with different scenarios in a single run" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      existing_token =
        insert(:oauth_token,
          user: user,
          oauth_client: oauth_client,
          scopes: ["read", "write", "profile"],
          body: %{
            "access_token" => "existing_token",
            "refresh_token" => "existing_refresh",
            "expires_at" => 3600,
            "scope" => "read write profile"
          }
        )

      already_migrated =
        insert(:credential,
          schema: "oauth",
          user: user,
          oauth_client: oauth_client,
          body: %{"apiVersion" => "v52.0"},
          oauth_token_id: existing_token.id
        )

      reuse_token =
        insert(:credential,
          schema: "oauth",
          user: user,
          oauth_client: oauth_client,
          body: %{
            "access_token" => "should_reuse_token",
            "refresh_token" => "should_reuse_refresh",
            "expires_at" => 3600,
            "scope" => "read write"
          },
          oauth_token_id: nil
        )

      new_token =
        insert(:credential,
          schema: "oauth",
          user: user,
          oauth_client: oauth_client,
          body: %{
            "access_token" => "needs_new_token",
            "refresh_token" => "needs_new_refresh",
            "expires_at" => 3600,
            "scope" => "admin"
          },
          oauth_token_id: nil
        )

      with_api_version =
        insert(:credential,
          schema: "oauth",
          user: user,
          oauth_client: oauth_client,
          body: %{
            "access_token" => "has_api_version",
            "refresh_token" => "has_api_version_refresh",
            "expires_at" => 3600,
            "scope" => "custom",
            "apiVersion" => "v53.0"
          },
          oauth_token_id: nil
        )

      non_oauth =
        insert(:credential,
          schema: "postgresql",
          user: user,
          body: %{"user" => "postgres"},
          oauth_token_id: nil
        )

      results = OauthMigration.run()

      assert results.credentials_updated == 3
      assert results.tokens_created == 2

      unchanged = Repo.get!(Credential, already_migrated.id)
      assert unchanged.oauth_token_id == existing_token.id
      assert unchanged.body == %{"apiVersion" => "v52.0"}

      reused = Repo.get!(Credential, reuse_token.id)
      assert reused.oauth_token_id == existing_token.id

      created_new = Repo.get!(Credential, new_token.id)
      assert created_new.oauth_token_id != nil
      assert created_new.oauth_token_id != existing_token.id

      preserved = Repo.get!(Credential, with_api_version.id)
      assert preserved.oauth_token_id != nil
      assert preserved.body == %{"apiVersion" => "v53.0"}

      skipped = Repo.get!(Credential, non_oauth.id)
      assert skipped.oauth_token_id == nil
      assert skipped.body == %{"user" => "postgres"}
    end
  end
end
