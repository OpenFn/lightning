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

      Lightning.CredentialHelpers.stub_oauth_client(
        oauth_client,
        {200,
         %{
           "access_token" => "ya29.a0AWY7CknfkidjXaoDTuNi",
           "expires_at" => new_expiry,
           "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
           "scope" => "https://www.googleapis.com/auth/spreadsheets",
           "token_type" => "Bearer"
         }}
      )

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

      Lightning.CredentialHelpers.stub_oauth_client(oauth_client, 429)

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

      Lightning.CredentialHelpers.stub_oauth_client(oauth_client, 500)

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
    test "is unsupported" do
      credential = insert(:keychain_credential)

      assert_raise FunctionClauseError, fn ->
        Resolver.resolve_credential(credential)
      end
    end
  end

  describe "resolve_credential/2 with keychain credential and run" do
    setup do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])

      # Create actual credentials that will be referenced by keychain via external_id
      credential_a =
        insert(:credential,
          name: "Alice DHIS2",
          body: %{
            "username" => "alice",
            "password" => "alice_pass",
            "hostUrl" => "https://dhis2.example.com"
          },
          schema: "dhis2",
          external_id: "alice_dhis2",
          user: user
        )

      credential_b =
        insert(:credential,
          name: "Bob DHIS2",
          body: %{
            "username" => "bob",
            "password" => "bob_pass",
            "hostUrl" => "https://dhis2.example.com"
          },
          schema: "dhis2",
          external_id: "123",
          user: user
        )

      default_credential =
        insert(:credential,
          name: "System DHIS2",
          body: %{
            "username" => "default",
            "password" => "default_pass",
            "hostUrl" => "https://dhis2.example.com"
          },
          schema: "dhis2",
          user: user
        )

      # Associate credentials with project
      for credential <- [credential_a, credential_b, default_credential] do
        insert(:project_credential, project: project, credential: credential)
      end

      # Create keychain credential using the factory
      keychain_credential =
        insert(:keychain_credential,
          name: "DHIS2 Multi-User Keychain",
          path: "$.user_id",
          default_credential: default_credential,
          project: project,
          created_by: user
        )

      %{jobs: [job]} =
        workflow =
        build(:workflow, project: project)
        |> with_job(%{keychain_credential: keychain_credential})
        |> insert()

      %{
        credential_a: credential_a,
        credential_b: credential_b,
        default_credential: default_credential,
        job: job,
        keychain_credential: keychain_credential,
        project: project,
        user: user,
        workflow: workflow
      }
    end

    test "resolves keychain credential using dataclip data", %{
      credential_a: credential_a,
      credential_b: credential_b,
      job: job,
      keychain_credential: keychain_credential,
      workflow: workflow
    } do
      %{runs: [run]} =
        insert(:workorder, workflow: workflow)
        |> with_run(%{
          # Create dataclip with user_id = "alice_dhis2" that matches alice's external_id
          dataclip:
            build(:dataclip, %{
              body: %{
                "user_id" => "alice_dhis2",
                "form_data" => %{"name" => "Test Form"}
              }
            }),
          starting_job: job
        })

      # Should resolve to credential_a based on JSONPath $.user_id
      # matching external_id
      assert {:ok, %Lightning.Credentials.ResolvedCredential{} = resolved} =
               Resolver.resolve_credential(run, keychain_credential.id)

      assert resolved.body == credential_a.body
      assert resolved.credential.id == credential_a.id

      # Specifically test that resolving values that are stored as integers
      # in the dataclip body are resolved correctly
      # External IDs are stored as strings, so we need to ensure that the
      # JSONPath query doesn't care if it's a string or an integer.

      keychain_credential
      |> Ecto.Changeset.change(path: "$.data.number_key")
      |> Repo.update!()

      %{runs: [run]} =
        insert(:workorder, workflow: workflow)
        |> with_run(%{
          dataclip:
            build(:dataclip, %{
              body: %{
                "data" => %{"number_key" => 123},
                "form_data" => %{"name" => "Test Form"}
              }
            }),
          starting_job: job
        })

      assert {:ok, %Lightning.Credentials.ResolvedCredential{} = resolved} =
               Resolver.resolve_credential(run, keychain_credential.id)

      assert resolved.body == credential_b.body
      assert resolved.credential.id == credential_b.id
    end

    test "falls back to default when JSONPath doesn't match dataclip", %{
      default_credential: default_credential,
      job: job,
      keychain_credential: keychain_credential,
      workflow: workflow
    } do
      %{runs: [run]} =
        insert(:workorder, workflow: workflow)
        |> with_run(%{
          # Create dataclip with user_id that doesn't match any credential's external_id
          dataclip:
            build(:dataclip, %{
              body: %{
                "user_id" => "charlie_dhis2",
                "form_data" => %{"name" => "Test Form"}
              }
            }),
          starting_job: job
        })

      # Should fall back to default_credential when no external_id matches
      assert {:ok, resolved} =
               Resolver.resolve_credential(run, keychain_credential.id)

      assert %Lightning.Credentials.ResolvedCredential{} = resolved
      assert resolved.body == default_credential.body
      assert resolved.credential.id == default_credential.id
    end

    test "returns nil when there is no matching or default credential", %{
      project: project,
      user: user
    } do
      keychain_credential =
        insert(:keychain_credential,
          name: "Without Default",
          path: "$.user_id",
          default_credential: nil,
          project: project,
          created_by: user
        )

      %{jobs: [job]} =
        workflow =
        build(:workflow, project: project)
        |> with_job(%{keychain_credential: keychain_credential})
        |> insert()

      %{runs: [run]} =
        insert(:workorder, workflow: workflow)
        |> with_run(%{
          dataclip:
            build(:dataclip, %{
              body: %{
                "user_id" => "charlie_dhis2",
                "form_data" => %{"name" => "Test Form"}
              }
            }),
          starting_job: job
        })

      assert {:ok, nil} =
               Resolver.resolve_credential(run, keychain_credential.id)
    end

    test "resolves keychain oauth credential and refreshes token", %{
      keychain_credential: keychain_credential,
      project: project,
      user: user
    } do
      # Create OAuth client and credential with expired token
      oauth_client = insert(:oauth_client)

      expires_at =
        DateTime.utc_now() |> DateTime.add(-299, :second) |> DateTime.to_unix()

      oauth_credential =
        insert(:credential,
          name: "Alice OAuth DHIS2",
          schema: "oauth",
          body: %{"sandbox" => false},
          external_id: "alice_oauth_dhis2",
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
          user: user,
          project_credentials: [%{project: project}]
        )

      %{jobs: [job]} =
        workflow =
        build(:workflow, project: project)
        |> with_job(%{keychain_credential: keychain_credential})
        |> insert()

      %{runs: [run]} =
        insert(:workorder, workflow: workflow)
        |> with_run(%{
          dataclip:
            build(:dataclip, %{
              body: %{
                "user_id" => "alice_oauth_dhis2",
                "form_data" => %{"name" => "Test Form"}
              }
            }),
          starting_job: job
        })

      new_expiry = expires_at + 3600

      # Stub OAuth refresh response
      Lightning.CredentialHelpers.stub_oauth_client(
        oauth_client,
        {200,
         %{
           "access_token" => "ya29.a0AWY7CknfkidjXaoDTuNi",
           "expires_at" => new_expiry,
           "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
           "scope" => "https://www.googleapis.com/auth/spreadsheets",
           "token_type" => "Bearer"
         }}
      )

      # Should resolve to OAuth credential and refresh the token
      assert {:ok, %Lightning.Credentials.ResolvedCredential{} = resolved} =
               Resolver.resolve_credential(run, keychain_credential.id)

      # Should have refreshed token data merged with credential body
      assert %{
               "sandbox" => false,
               "access_token" => "ya29.a0AWY7CknfkidjXaoDTuNi",
               "expires_at" => ^new_expiry,
               "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
               "scope" => "https://www.googleapis.com/auth/spreadsheets",
               "token_type" => "Bearer",
               "updated_at" => _updated_at
             } = resolved.body

      assert resolved.credential.id == oauth_credential.id
    end

    @tag skip: true
    test "handles nested JSONPath expressions in keychain" do
    end
  end

  describe "resolve_credential/2 with run and credential id" do
    setup do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])
      %{user: user, project: project}
    end

    test "resolves credential accessible by run", %{project: project, user: user} do
      credential =
        insert(:credential,
          user: user,
          name: "Test Credential",
          body: %{"key" => "value"}
        )

      %{jobs: [job]} =
        workflow =
        build(:workflow, project: project)
        |> with_job(%{
          project_credential: %{credential: credential, project: project}
        })
        |> insert()

      dataclip = insert(:dataclip)

      %{runs: [run]} =
        insert(:workorder, workflow: workflow)
        |> with_run(%{dataclip: dataclip, starting_job: job})

      assert {:ok, resolved} = Resolver.resolve_credential(run, credential.id)
      assert %Lightning.Credentials.ResolvedCredential{} = resolved
      assert resolved.body == %{"key" => "value"}
      assert resolved.credential.id == credential.id
    end

    test "returns not_found when credential doesn't exist", %{user: user} do
      project = insert(:project, project_users: [%{user: user}])

      %{jobs: [job]} =
        workflow =
        build(:workflow, project: project)
        |> with_job()
        |> insert()

      dataclip = insert(:dataclip)

      %{runs: [run]} =
        insert(:workorder, workflow: workflow)
        |> with_run(%{dataclip: dataclip, starting_job: job})

      fake_id = Ecto.UUID.generate()
      assert {:error, :not_found} = Resolver.resolve_credential(run, fake_id)
    end

    test "returns not_found when credential exists but not accessible by run", %{
      user: user
    } do
      project = insert(:project, project_users: [%{user: user}])
      other_credential = insert(:credential, user: user)

      %{jobs: [job]} =
        workflow =
        build(:workflow, project: project)
        |> with_job()
        |> insert()

      dataclip = insert(:dataclip)

      %{runs: [run]} =
        insert(:workorder, workflow: workflow)
        |> with_run(%{dataclip: dataclip, starting_job: job})

      assert {:error, :not_found} =
               Resolver.resolve_credential(run, other_credential.id)
    end
  end
end
