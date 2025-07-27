defmodule ResolverTest do
  use Lightning.DataCase, async: true

  alias Lightning.Credentials.Resolver

  import Lightning.Factories

  describe "resolve_credential/1 with regular credential" do
    test "returns ResolvedCredential with credential body" do
      user = insert(:user)

      credential =
        insert(:credential,
          name: "Test Postgres",
          body: %{
            "user" => "user1",
            "password" => "pass1",
            "host" => "https://dbhost",
            "port" => "5000",
            "database" => "test_db",
            "ssl" => "true",
            "allowSelfSignedCert" => "false"
          },
          schema: "postgresql",
          user: user
        )

      assert {:ok, resolved} = Resolver.resolve_credential(credential)
      assert %Lightning.Credentials.ResolvedCredential{} = resolved
      assert resolved.body == credential.body
      assert resolved.credential == credential
    end

    test "removes empty string values from credential body" do
      user = insert(:user)

      credential =
        insert(:credential,
          name: "Test Commcare",
          body: %{
            "apiKey" => "",
            "appId" => "12345",
            "domain" => "localhost",
            "hostUrl" => "http://localhost:2500",
            "password" => "test",
            "username" => ""
          },
          schema: "commcare",
          user: user
        )

      assert {:ok, resolved} = Resolver.resolve_credential(credential)

      # Empty strings should be removed
      expected_body = %{
        "appId" => "12345",
        "domain" => "localhost",
        "hostUrl" => "http://localhost:2500",
        "password" => "test"
      }

      assert resolved.body == expected_body
      assert resolved.credential == credential
    end
  end

  describe "resolve_credential/1 with oauth credential" do
    setup do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      %{user: user, oauth_client: oauth_client}
    end

    test "with valid token merges token into body", %{
      user: user,
      oauth_client: oauth_client
    } do
      oauth_token_body = %{
        "access_token" => "valid_access_token",
        "refresh_token" => "valid_refresh_token",
        "expires_at" =>
          DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_unix()
      }

      credential =
        insert(:credential,
          name: "OAuth Test",
          schema: "oauth",
          body: %{"apiVersion" => 23, "sandbox" => true},
          oauth_client: oauth_client,
          oauth_token:
            build(:oauth_token,
              body: oauth_token_body,
              user: user,
              oauth_client: oauth_client
            ),
          user: user
        )

      # Preload the credential with oauth_token for proper resolution
      credential = Repo.preload(credential, oauth_token: [:oauth_client])

      assert {:ok, resolved} = Resolver.resolve_credential(credential)
      assert %Lightning.Credentials.ResolvedCredential{} = resolved

      # Should merge oauth token body with credential body
      expected_body = %{
        "apiVersion" => 23,
        "sandbox" => true,
        "access_token" => "valid_access_token",
        "refresh_token" => "valid_refresh_token",
        "expires_at" => oauth_token_body["expires_at"]
      }

      assert resolved.body == expected_body
      assert resolved.credential.id == credential.id
    end

    test "removes empty values from merged OAuth credential body", %{
      user: user,
      oauth_client: oauth_client
    } do
      oauth_token_body = %{
        "access_token" => "valid_access_token",
        # Empty string should be removed
        "refresh_token" => "",
        "expires_at" =>
          DateTime.utc_now() |> DateTime.add(3600) |> DateTime.to_unix()
      }

      credential =
        insert(:credential,
          name: "OAuth Test",
          schema: "oauth",
          # Empty sandbox should be removed
          body: %{
            "apiVersion" => 23,
            "sandbox" => "",
            "instanceUrl" => "https://test.com"
          },
          oauth_client: oauth_client,
          oauth_token:
            build(:oauth_token,
              body: oauth_token_body,
              user: user,
              oauth_client: oauth_client
            ),
          user: user
        )

      # Preload the credential with oauth_token for proper resolution
      credential = Repo.preload(credential, oauth_token: [:oauth_client])

      assert {:ok, resolved} = Resolver.resolve_credential(credential)
      assert %Lightning.Credentials.ResolvedCredential{} = resolved

      # Should merge oauth token body with credential body and remove empty values
      expected_body = %{
        "apiVersion" => 23,
        "instanceUrl" => "https://test.com",
        "access_token" => "valid_access_token",
        "expires_at" => oauth_token_body["expires_at"]
        # "sandbox" and "refresh_token" should be removed due to empty strings
      }

      assert resolved.body == expected_body
      assert resolved.credential.id == credential.id
    end

    test "with expired token refreshes and merges", %{
      user: user,
      oauth_client: oauth_client
    } do
      expires_at =
        DateTime.utc_now() |> DateTime.add(-299, :second) |> DateTime.to_unix()

      oauth_token_body = %{
        "access_token" => "expired_access_token",
        "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
        "expires_at" => expires_at
      }

      credential =
        insert(:credential,
          name: "Test Googlesheets Credential",
          schema: "oauth",
          body: %{"sandbox" => false},
          oauth_client: oauth_client,
          oauth_token:
            build(:oauth_token,
              body: oauth_token_body,
              user: user,
              oauth_client: oauth_client
            ),
          user: user
        )

      new_expiry = expires_at + 3600
      endpoint = oauth_client.token_endpoint

      Mox.expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        %Tesla.Env{method: :post, url: ^endpoint} = env, _opts ->
          {:ok,
           %Tesla.Env{
             env
             | status: 200,
               body: %{
                 "access_token" => "ya29.a0AWY7CknfkidjXaoDTuNi",
                 "expires_at" => new_expiry,
                 "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
                 "scope" => "https://www.googleapis.com/auth/spreadsheets",
                 "token_type" => "Bearer"
               }
           }}
      end)

      # Preload the credential with oauth_token for proper resolution
      credential = Repo.preload(credential, oauth_token: [:oauth_client])

      assert {:ok, resolved} = Resolver.resolve_credential(credential)
      assert %Lightning.Credentials.ResolvedCredential{} = resolved

      # Should have refreshed token data merged with credential body
      # Note: updated_at is added by the OAuth refresh process
      assert %{
               "sandbox" => false,
               "access_token" => "ya29.a0AWY7CknfkidjXaoDTuNi",
               "expires_at" => ^new_expiry,
               "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
               "scope" => "https://www.googleapis.com/auth/spreadsheets",
               "token_type" => "Bearer",
               "updated_at" => _updated_at
             } = resolved.body

      assert resolved.credential.id == credential.id
    end

    test "when refresh fails with invalid_grant returns reauthorization_required error",
         %{user: user, oauth_client: oauth_client} do
      expires_at =
        DateTime.utc_now() |> DateTime.add(-299, :second) |> DateTime.to_unix()

      credential =
        insert(:credential,
          name: "Test Googlesheets Credential",
          schema: "oauth",
          body: %{"sandbox" => false},
          oauth_client: oauth_client,
          oauth_token:
            build(:oauth_token,
              body: %{
                "access_token" => "expired_access_token",
                "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
                "expires_at" => expires_at
              },
              user: user,
              oauth_client: oauth_client
            ),
          user: user
        )

      endpoint = oauth_client.token_endpoint

      Mox.expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        %Tesla.Env{method: :post, url: ^endpoint} = env, _opts ->
          {:ok,
           %Tesla.Env{
             env
             | status: 400,
               body: %{"error" => "invalid_grant"}
           }}
      end)

      # Preload the credential with oauth_token for proper resolution
      credential = Repo.preload(credential, oauth_token: [:oauth_client])

      assert {:error, {:reauthorization_required, credential}} =
               Resolver.resolve_credential(credential)

      assert credential.name == "Test Googlesheets Credential"
    end

    test "when refresh fails with rate limit returns temporary_failure error", %{
      user: user,
      oauth_client: oauth_client
    } do
      expires_at =
        DateTime.utc_now() |> DateTime.add(-299, :second) |> DateTime.to_unix()

      credential =
        insert(:credential,
          name: "Test Googlesheets Credential",
          schema: "oauth",
          body: %{"sandbox" => false},
          oauth_client: oauth_client,
          oauth_token:
            build(:oauth_token,
              body: %{
                "access_token" => "expired_access_token",
                "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
                "expires_at" => expires_at
              },
              user: user,
              oauth_client: oauth_client
            ),
          user: user
        )

      endpoint = oauth_client.token_endpoint

      Mox.expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        %Tesla.Env{method: :post, url: ^endpoint} = env, _opts ->
          {:ok,
           %Tesla.Env{
             env
             | status: 429,
               body: %{"error" => "rate limit"}
           }}
      end)

      # Preload the credential with oauth_token for proper resolution
      credential = Repo.preload(credential, oauth_token: [:oauth_client])

      assert {:error, {:temporary_failure, _credential}} =
               Resolver.resolve_credential(credential)
    end

    test "when refresh fails with other error returns generic error", %{
      user: user,
      oauth_client: oauth_client
    } do
      expires_at =
        DateTime.utc_now() |> DateTime.add(-299, :second) |> DateTime.to_unix()

      credential =
        insert(:credential,
          name: "Test Googlesheets Credential",
          schema: "oauth",
          body: %{"sandbox" => false},
          oauth_client: oauth_client,
          oauth_token:
            build(:oauth_token,
              body: %{
                "access_token" => "expired_access_token",
                "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
                "expires_at" => expires_at
              },
              user: user,
              oauth_client: oauth_client
            ),
          user: user
        )

      endpoint = oauth_client.token_endpoint

      Mox.expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        %Tesla.Env{method: :post, url: ^endpoint} = env, _opts ->
          {:ok,
           %Tesla.Env{
             env
             | status: 500,
               body: %{"error" => "internal_server_error"}
           }}
      end)

      # Preload the credential with oauth_token for proper resolution
      credential = Repo.preload(credential, oauth_token: [:oauth_client])

      assert {:error, {original_error, _credential}} =
               Resolver.resolve_credential(credential)

      # Should return the original error for generic failures
      assert original_error != :reauthorization_required
      assert original_error != :temporary_failure
    end
  end

  describe "resolve_credential/1 with keychain credential" do
    @tag skip: true
    test "resolves to regular credential using JSONPath"

    @tag skip: true
    test "falls back to default when path doesn't match"

    @tag skip: true
    test "returns error when no match and no default"

    @tag skip: true
    test "resolves and refreshes oauth token if needed"
  end

  describe "resolve_credential/2 with run and credential id" do
    setup do
      user = insert(:user)
      %{user: user}
    end

    test "resolves credential accessible by run", %{user: user} do
      project = insert(:project, project_users: [%{user: user}])

      credential =
        insert(:credential,
          user: user,
          name: "Test Credential",
          body: %{"key" => "value"}
        )

      job = insert(:job, project_credential: %{credential: credential})
      workflow = insert(:workflow, project: project, jobs: [job])
      work_order = insert(:workorder, workflow: workflow)
      dataclip = insert(:dataclip)

      run =
        insert(:run,
          work_order: work_order,
          dataclip: dataclip,
          starting_job: job
        )

      assert {:ok, resolved} = Resolver.resolve_credential(run, credential.id)
      assert %Lightning.Credentials.ResolvedCredential{} = resolved
      assert resolved.body == %{"key" => "value"}
      assert resolved.credential.id == credential.id
    end

    test "returns not_found when credential doesn't exist", %{user: user} do
      project = insert(:project, project_users: [%{user: user}])
      job = insert(:job)
      workflow = insert(:workflow, project: project, jobs: [job])
      work_order = insert(:workorder, workflow: workflow)
      dataclip = insert(:dataclip)

      run =
        insert(:run,
          work_order: work_order,
          dataclip: dataclip,
          starting_job: job
        )

      fake_id = Ecto.UUID.generate()
      assert {:error, :not_found} = Resolver.resolve_credential(run, fake_id)
    end

    test "returns not_found when credential exists but not accessible by run", %{
      user: user
    } do
      project = insert(:project, project_users: [%{user: user}])
      other_credential = insert(:credential, user: user)

      job = insert(:job)
      workflow = insert(:workflow, project: project, jobs: [job])
      work_order = insert(:workorder, workflow: workflow)
      dataclip = insert(:dataclip)

      run =
        insert(:run,
          work_order: work_order,
          dataclip: dataclip,
          starting_job: job
        )

      assert {:error, :not_found} =
               Resolver.resolve_credential(run, other_credential.id)
    end
  end

  describe "resolve_credential/1 error cases" do
    @tag skip: true
    test "returns not_found error when credential doesn't exist"

    @tag skip: true
    test "returns not_found error when credential exists but not accessible by run"
  end
end
