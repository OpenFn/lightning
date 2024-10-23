defmodule Lightning.CredentialsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Auditing
  alias Lightning.Credentials
  alias Lightning.Credentials.{Audit, Credential}
  alias Lightning.CredentialsFixtures
  alias Lightning.Repo

  import Lightning.BypassHelpers
  import Lightning.Factories
  import Ecto.Query
  import Mox

  import Lightning.{
    AccountsFixtures,
    CredentialsFixtures,
    JobsFixtures,
    ProjectsFixtures
  }

  import Swoosh.TestAssertions

  setup :verify_on_exit!

  describe "Model interactions" do
    @invalid_attrs %{body: nil, name: nil}

    test "list_credentials/1 returns all credentials for given user" do
      user_1 = user_fixture()
      user_2 = user_fixture()

      credential_1 =
        credential_fixture(user_id: user_1.id)
        |> Repo.preload([:projects, :oauth_client])

      credential_2 =
        credential_fixture(user_id: user_2.id)
        |> Repo.preload([:projects, :oauth_client])

      assert Credentials.list_credentials(user_1) == [
               credential_1
             ]

      assert Credentials.list_credentials(user_2) == [
               credential_2
             ]
    end

    test "list_credentials/1 returns all credentials for a project" do
      user = user_fixture()
      project = project_fixture(project_users: [%{user_id: user.id}])

      credential =
        credential_fixture(
          user_id: user.id,
          user: user,
          project_credentials: [%{project_id: project.id}]
        )
        |> Repo.preload([:user, :projects, :oauth_client])

      assert Credentials.list_credentials(project) == [credential]
    end

    test "get_credential!/1 returns the credential with given id" do
      user = insert(:user)
      credential = insert(:credential, user_id: user.id)
      assert Credentials.get_credential!(credential.id) == credential
    end

    test "delete_credential/1 deletes a credential and removes it from associated jobs and projects" do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{role: :owner, user_id: user.id}])

      project_credential =
        insert(:project_credential,
          project: project,
          credential: build(:credential, user: user)
        )

      credential_id = project_credential.credential_id

      %{job: job} =
        workflow_job_fixture(
          project: project,
          project_credential: project_credential
        )

      # 1 project_credential created
      assert length(
               Lightning.Projects.list_project_credentials(
                 %Lightning.Projects.Project{
                   id: project_credential.project_id
                 }
               )
             ) == 1

      assert {:ok,
              %{
                audit: %Lightning.Auditing.Audit{} = audit,
                credential: %Credential{} = credential
              }} =
               Credentials.delete_credential(%Lightning.Credentials.Credential{
                 id: credential_id,
                 user_id: user.id
               })

      assert audit.event == "deleted"
      assert audit.item_id == credential_id

      # previous  audit records are not deleted
      # a new audit (event: deleted) is added
      assert from(a in Audit.base_query(),
               where: a.item_id == ^credential.id
             )
             |> Repo.all()
             |> Enum.all?(fn a ->
               a.item_id == credential.id &&
                 a.event in ["created", "updated", "deleted", "added_to_project"]
             end)

      assert_raise Ecto.NoResultsError, fn ->
        Credentials.get_credential!(credential.id)
      end

      # no more project_credentials
      assert Enum.empty?(
               Lightning.Projects.list_project_credentials(
                 %Lightning.Projects.Project{
                   id: project_credential.project_id
                 }
               )
             )

      job = Repo.get!(Lightning.Workflows.Job, job.id)

      assert job.project_credential_id == nil
    end

    test "schedule_credential_deletion/1 schedules a deletion date according to the :purge_deleted_after_days env" do
      days = Lightning.Config.purge_deleted_after_days()

      user = insert(:user)
      project = build(:project) |> with_project_user(user, :owner) |> insert()

      credential =
        insert(:credential,
          name: "My Credential",
          body: %{foo: :bar},
          user: user
        )

      project_credential =
        insert(:project_credential, credential: credential, project: project)

      job = insert(:job, project_credential: project_credential)

      # Ensure associations are existent before deletion
      initial_project_credentials =
        Repo.all(assoc(credential, :project_credentials))

      assert not Enum.empty?(initial_project_credentials)

      initial_job = Repo.reload!(job)
      assert initial_job.project_credential_id == project_credential.id

      refute_email_sent()

      assert credential.scheduled_deletion == nil

      now = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, updated_credential} =
        Credentials.schedule_credential_deletion(credential)

      # Ensure scheduled_deletion is updated as expected
      assert updated_credential.scheduled_deletion != nil

      assert Timex.diff(updated_credential.scheduled_deletion, now, :days) ==
               days

      # Verify project_credential association removal
      retrieved_project_credentials =
        Repo.all(assoc(updated_credential, :project_credentials))

      assert Enum.empty?(retrieved_project_credentials)

      # Verify job's credential_id is set to nil
      retrieved_job = Repo.reload!(job)
      assert is_nil(retrieved_job.project_credential_id)

      assert_email_sent(
        subject: "Your \"#{credential.name}\" credential will be deleted",
        to: Swoosh.Email.Recipient.format(user)
      )
    end

    test "schedule_credential_deletion/1 revokes token for oauth credentials" do
      oauth_credential =
        insert(:credential,
          name: "My Credential",
          schema: "oauth",
          body: %{
            "access_token" => "super_secret_access_token_123",
            "refresh_token" => "super_secret_refresh_token_123",
            "expires_in" => 3000
          },
          user: build(:user),
          oauth_client: build(:oauth_client)
        )

      refute oauth_credential.scheduled_deletion

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        env, _opts
        when env.method == :post and
               env.url == "http://example.com/oauth2/revoke" ->
          {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{})}}
      end)

      {:ok, oauth_credential} =
        Credentials.schedule_credential_deletion(oauth_credential)

      assert oauth_credential.scheduled_deletion
    end

    test "cancel_scheduled_deletion/1 sets scheduled_deletion to nil for a given credential" do
      # Set up a credential with a scheduled_deletion date
      # 1 hour from now, truncated to seconds
      scheduled_date =
        DateTime.utc_now() |> DateTime.add(3600) |> DateTime.truncate(:second)

      credential =
        insert(:credential,
          user: insert(:user),
          name: "My Credential",
          body: %{foo: :bar},
          scheduled_deletion: scheduled_date
        )

      # Ensure the initial setup is correct
      assert DateTime.truncate(credential.scheduled_deletion, :second) ==
               scheduled_date

      # Call the function to cancel the scheduled deletion
      {:ok, updated_credential} =
        Credentials.cancel_scheduled_deletion(credential.id)

      # Verify the scheduled_deletion field is set to nil
      assert is_nil(updated_credential.scheduled_deletion)
    end

    test "change_credential/1 returns a credential changeset" do
      user = insert(:user)
      credential = insert(:credential, user_id: user.id)
      assert %Ecto.Changeset{} = Credentials.change_credential(credential)
    end

    test "invalid_projects_for_user/2 returns a list of invalid projects, given a credential and a user" do
      %{id: user_id_1} = insert(:user)
      %{id: user_id_2} = insert(:user)
      %{id: user_id_3} = insert(:user)

      %Lightning.Projects.Project{id: project_id} =
        insert(:project,
          name: "some-name",
          project_users: [%{user_id: user_id_1}, %{user_id: user_id_2}]
        )

      credential =
        insert(:credential,
          user_id: user_id_1,
          project_credentials: [%{project_id: project_id}]
        )

      assert Credentials.invalid_projects_for_user(
               credential.id,
               user_id_2
             ) == []

      assert Credentials.invalid_projects_for_user(
               credential.id,
               user_id_3
             ) ==
               [project_id]
    end
  end

  describe "get_credential_by_project_credential/1" do
    test "sreturns the credential with given project_credential id" do
      refute Credentials.get_credential_by_project_credential(
               Ecto.UUID.generate()
             )

      project_credential = insert(:project_credential)

      credential =
        Credentials.get_credential_by_project_credential(project_credential.id)

      assert credential.id == project_credential.credential.id
    end
  end

  describe "create_credential/1" do
    test "fails if another cred exists with the same name for the same user" do
      valid_attrs = %{
        body: %{"a" => "test"},
        name: "simple name",
        user_id: insert(:user).id,
        schema: "raw"
      }

      assert {:ok, %Credential{}} = Credentials.create_credential(valid_attrs)

      assert {
               :error,
               %Ecto.Changeset{
                 errors: [
                   name:
                     {"you have another credential with the same name",
                      [
                        constraint: :unique,
                        constraint_name: "credentials_name_user_id_index"
                      ]}
                 ]
               }
             } = Credentials.create_credential(valid_attrs)
    end

    test "suceeds with raw schema" do
      valid_attrs = %{
        body: %{"username" => "user", "password" => "pass", "port" => 5000},
        name: "some raw credential",
        user_id: insert(:user).id,
        schema: "raw",
        project_credentials: [
          %{project_id: insert(:project).id}
        ]
      }

      assert {:ok, %Credential{} = credential} =
               Credentials.create_credential(valid_attrs)

      assert credential.body == %{
               "username" => "user",
               "password" => "pass",
               "port" => 5000
             }

      assert credential.name == "some raw credential"

      assert audit_event =
               from(a in Audit.base_query(),
                 where: a.item_id == ^credential.id and a.event == "created"
               )
               |> Repo.one!(),
             "Has exactly one 'created' event"

      assert audit_event.changes.before |> is_nil()
      assert audit_event.changes.after["name"] == credential.name

      # If we decode and then decrypt the audit trail event with, we'll see the
      # raw credential body again.
      assert audit_event.changes.after["body"]
             |> Base.decode64!()
             |> Lightning.Encrypted.Map.load() == {:ok, credential.body}
    end

    test "saves the body casting non string fields" do
      body = %{
        "user" => "user1",
        "password" => "pass1",
        "host" => "https://dbhost",
        "database" => "test_db",
        "port" => "5000",
        "ssl" => "true",
        "allowSelfSignedCert" => "false"
      }

      valid_attrs = %{
        body: body,
        name: "some name",
        user_id: insert(:user).id,
        schema: "postgresql",
        project_credentials: [
          %{project_id: insert(:project).id}
        ]
      }

      assert {:ok, %Credential{} = credential} =
               Credentials.create_credential(valid_attrs)

      assert credential.body ==
               Map.merge(body, %{
                 "port" => 5000,
                 "ssl" => true,
                 "allowSelfSignedCert" => false
               })

      assert credential.name == "some name"

      assert audit_event =
               from(a in Audit.base_query(),
                 where: a.item_id == ^credential.id and a.event == "created"
               )
               |> Repo.one!(),
             "Has exactly one 'created' event"

      assert audit_event.changes.before |> is_nil()
      assert audit_event.changes.after["name"] == credential.name

      {:ok, saved_body} =
        audit_event.changes.after["body"]
        |> Base.decode64!()
        |> Lightning.Encrypted.Map.load()

      assert saved_body == credential.body
    end

    test "fails with invalid data" do
      assert {:error, %Ecto.Changeset{}} =
               Credentials.create_credential(@invalid_attrs)
    end
  end

  describe "update_credential/2" do
    test "updates an Oauth credential with new scopes" do
      credential =
        credential_fixture(
          body: %{
            "access_token" => "ya29.a0AWY7CknfkidjXaoDTuNi",
            "expires_at" => 10_000,
            "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
            "scope" => "email calendar chat"
          },
          schema: "oauth"
        )

      update_attrs = %{
        body: %{
          "access_token" => "ya29.a0AWY7CknfkidjXaoDTuNi",
          "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
          "expires_at" => 10_000,
          "scope" => "email calendar"
        }
      }

      assert {:ok, %Credential{} = credential} =
               Credentials.update_credential(credential, update_attrs)

      assert credential.body == %{
               "access_token" => "ya29.a0AWY7CknfkidjXaoDTuNi",
               "expires_at" => 10000,
               "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
               "scope" => "email calendar"
             }
    end

    test "succeeds with valid data and associating with new project" do
      user = insert(:user)

      project =
        insert(:project, name: "some-name", project_users: [%{user_id: user.id}])

      credential =
        insert(:credential,
          body: %{},
          name: "some name",
          schema: "raw",
          user: user,
          project_credentials: [
            %{project_id: project.id}
          ]
        )

      original_project_credential =
        Enum.at(credential.project_credentials, 0)
        |> Map.from_struct()

      new_project = insert(:project)

      update_attrs = %{
        body: %{},
        name: "some updated name",
        project_credentials: [
          original_project_credential,
          %{project_id: new_project.id}
        ]
      }

      assert {:ok, %Credential{} = credential} =
               Credentials.update_credential(credential, update_attrs)

      assert credential.body == %{}
      assert credential.name == "some updated name"

      assert %{project_credentials: project_credentials} =
               credential |> Repo.preload(:project_credentials)

      assert MapSet.new(Enum.map(project_credentials, & &1.project_id)) ==
               MapSet.new([project.id, new_project.id])

      audit_events =
        from(a in Audit.base_query(),
          where: a.item_id == ^credential.id,
          select: {a.event, type(a.changes, :map)}
        )
        |> Repo.all()

      assert {"updated",
              %{
                "before" => %{"name" => "some name"},
                "after" => %{"name" => "some updated name"}
              }} in audit_events

      assert {"added_to_project",
              %{
                "before" => %{"project_id" => nil},
                "after" => %{"project_id" => new_project.id}
              }} in audit_events
    end

    test "correctly handle removing credential from a project" do
      %{id: user_id} = user = insert(:user)

      %{id: project_id} =
        insert(:project, name: "some-name", project_users: [%{user_id: user_id}])

      credential =
        insert(:credential,
          body: %{},
          name: "some name",
          schema: "raw",
          user: user,
          project_credentials: [
            %{project_id: project_id}
          ]
        )

      %{
        id: credential_id,
        project_credentials: [%{id: project_credential_id}]
      } = credential

      removal_attrs = %{
        "body" => %{},
        "name" => "some name",
        "project_credentials" => [
          %{
            "delete" => "true",
            "id" => project_credential_id,
            "project_id" => project_id
          }
        ],
        "user_id" => user_id
      }

      assert {:ok, %Credential{} = updated_credential} =
               Credentials.update_credential(credential, removal_attrs)

      assert Enum.empty?(updated_credential.project_credentials)

      updated_event_query = from a in Auditing.Audit, where: a.event == "updated"

      assert %{
               item_id: ^credential_id,
               item_type: "credential",
               actor_id: ^user_id,
               actor_type: :user,
               changes: %{
                 before: %{},
                 after: nil
               }
             } = Repo.one!(updated_event_query)

      removed_event_query =
        from a in Auditing.Audit,
          where: a.event == "removed_from_project"

      assert %{
               item_id: ^credential_id,
               item_type: "credential",
               actor_id: ^user_id,
               actor_type: :user,
               changes: %{
                 before: %{"project_id" => ^project_id},
                 after: %{"project_id" => nil}
               }
             } = Repo.one!(removed_event_query)
    end

    test "casts body to field types based on schema" do
      user = insert(:user)

      project =
        insert(:project, name: "some-name", project_users: [%{user_id: user.id}])

      credential =
        insert(:credential,
          name: "Test Postgres",
          user_id: user.id,
          body: %{
            user: "user1",
            password: "pass1",
            host: "https://dbhost",
            database: "test_db",
            port: "5000",
            ssl: "true",
            allowSelfSignedCert: "false"
          },
          project_credentials: [
            %{project_id: project.id}
          ],
          schema: "postgresql"
        )

      new_body_attrs = %{
        "user" => "user1",
        "password" => "pass1",
        "host" => "https://dbhost",
        "database" => "test_db",
        "port" => "5002",
        "ssl" => "true",
        "allowSelfSignedCert" => "false"
      }

      assert {:ok, %Credential{body: updated_body}} =
               Credentials.update_credential(credential, %{
                 body: new_body_attrs
               })

      assert updated_body ==
               Map.merge(new_body_attrs, %{
                 "port" => 5002,
                 "ssl" => true,
                 "allowSelfSignedCert" => false
               })
    end

    test "raise error when credential doesn't have the latest project credentials" do
      user = insert(:user)

      project1 =
        insert(:project,
          project_users: [%{user_id: user.id}]
        )

      project2 =
        insert(:project,
          project_users: [%{user_id: user.id}]
        )

      %{
        project_credentials: [
          %{id: project_credential_id1},
          %{id: _project_credential_id2}
        ]
      } =
        credential =
        insert(:credential,
          user_id: user.id,
          body: %{
            a: "1"
          },
          project_credentials: [
            %{project_id: project1.id},
            %{project_id: project2.id}
          ],
          schema: "raw"
        )
        |> Repo.preload(:project_credentials)

      params_with_missing_project_credential = %{
        "body" => Jason.encode!(%{a: 2}),
        "name" => credential.name,
        "production" => "false",
        "project_credentials" => %{
          "0" => %{
            "_persistent_id" => "0",
            "delete" => "false",
            "id" => project_credential_id1,
            "project_id" => project1.id
          }
        }
      }

      assert_raise RuntimeError,
                   ~r/.*`:on_replace` option of this relation\nis set to `:raise`.*/,
                   fn ->
                     Credentials.update_credential(
                       credential,
                       params_with_missing_project_credential
                     )
                   end
    end

    test "returns error changeset with invalid data" do
      user = insert(:user)
      credential = insert(:credential, user_id: user.id)

      assert {:error, %Ecto.Changeset{}} =
               Credentials.update_credential(credential, @invalid_attrs)

      assert credential == Credentials.get_credential!(credential.id)
    end
  end

  describe "has_activity_in_projects?/1" do
    setup do
      {:ok, credential: insert(:credential)}
    end

    test "returns true when there's at least one associated step", %{
      credential: credential
    } do
      insert(:step, credential: credential)
      assert Credentials.has_activity_in_projects?(credential)
    end

    test "returns false when there's no associated step", %{
      credential: credential
    } do
      refute Credentials.has_activity_in_projects?(credential)
    end
  end

  describe "get_sensitive_values/1" do
    test "collects up all values" do
      credential =
        credential_fixture(
          body: %{
            "loginUrl" => "https://login.salesforce.com",
            "user" => %{
              "email" => "demo@openfn.org",
              "password" => "shhh",
              "scopes" => ["read/write", "admin"]
            },
            "security_token" => nil,
            "port" => 75
          }
        )

      secrets = ["admin", "read/write", "shhh", 75]

      assert Credentials.sensitive_values_for(credential) == secrets
      assert Credentials.sensitive_values_for(credential.id) == secrets
    end
  end

  # TODO: Remove this function when deprecating salesforce and googlesheets oauth
  describe "maybe_refresh_token/1 to remove" do
    test "doesn't refresh non OAuth credentials" do
      credential = CredentialsFixtures.credential_fixture()
      {:ok, refreshed_credential} = Credentials.maybe_refresh_token(credential)
      assert credential == refreshed_credential
    end

    test "doesn't refresh fresh OAuth credentials" do
      # now + 6 minutes
      expires_at = DateTime.to_unix(DateTime.utc_now()) + 6 * 60

      credential =
        credential_fixture(
          body: %{
            "access_token" => "ya29.a0AWY7CknfkidjXaoDT...",
            "expires_at" => expires_at,
            "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGA...",
            "scope" => "https://www.googleapis.com/auth/spreadsheets"
          },
          schema: "salesforce_oauth"
        )

      {:ok, refreshed_credential} = Credentials.maybe_refresh_token(credential)

      assert refreshed_credential.body["access_token"] ==
               credential.body["access_token"]

      assert refreshed_credential.body["expires_at"] ==
               credential.body["expires_at"]

      assert refreshed_credential == credential
    end

    test "refreshes OAuth credentials when they are about to expire" do
      bypass = Bypass.open()

      [
        %{provider: :google, schema: "googlesheets"},
        %{provider: :salesforce, schema: "salesforce_oauth"}
      ]
      |> Enum.each(fn oauth ->
        Lightning.ApplicationHelpers.put_temporary_env(
          :lightning,
          :oauth_clients,
          [
            {oauth.provider,
             [
               client_id: "client_id",
               client_secret: "secret",
               wellknown_url: "http://localhost:#{bypass.port}/auth/.well-known",
               prod_wellknown_url:
                 "http://localhost:#{bypass.port}/auth/.well-known",
               sandbox_wellknown_url:
                 "http://localhost:#{bypass.port}/auth/.well-known"
             ]}
          ]
        )

        wellknown_url = "http://localhost:#{bypass.port}/auth/.well-known"

        expect_wellknown(bypass)

        expect_token(
          bypass,
          Lightning.AuthProviders.Common.get_wellknown!(wellknown_url)
        )

        expect_introspect(
          bypass,
          Lightning.AuthProviders.Common.get_wellknown!(wellknown_url)
        )

        credential =
          credential_fixture(
            body: %{
              "access_token" => "ya29.a0AWY7CknfkidjXaoDTuNi",
              "expires_at" => 1000,
              "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
              "scope" => "https://www.googleapis.com/auth/spreadsheets"
            },
            schema: oauth.schema
          )

        # Attempt to refresh the OAuth credentials
        {:ok, refreshed_credential} = Credentials.maybe_refresh_token(credential)

        # Assertions to verify that the credentials were indeed refreshed
        refute refreshed_credential == credential,
               "Expected credentials to be refreshed for #{oauth.provider |> Atom.to_string()}"

        assert refreshed_credential.body["expires_at"] >
                 credential.body["expires_at"],
               "Expected new expiry to be greater than the old expiry for #{oauth.provider |> Atom.to_string()}"
      end)
    end

    test "doesn't refresh oauth credentials when they're oauth client is nil" do
      rotten_token = %{
        "access_token" =>
          "00DWS000000fDCb!AQEAQHRBgVJ4Bbb4XTr218Sn672cpnALW9FMkaATpdh8EwLhEJiNUrHg0eHiCBqHOh06F3pIyJym5gx4YD1vFv2fomMOOdzF",
        "apiVersion" => "",
        "expires_at" => 1000,
        "id" =>
          "https://login.salesforce.com/id/00DWS000000fDCb2AM/005WS000000OYRxYAO",
        "instance_url" => "https://ciddiqia-dev-ed.develop.my.salesforce.com",
        "issued_at" => "1715970504545",
        "refresh_token" =>
          "5Aep861z1aTCxS7eDOBJfa.2w9vR3Zh1uBh.2j6mBITbTXHOFonbXeWCjVyVMQsWJY9wekHK4diVJzLmt8avLvC",
        "scope" => "refresh_token",
        "signature" => "H6q34zM7qKZcX8NF05WtGGhn6/Lian9p4PgN/OVdvtk=",
        "token_type" => "Bearer"
      }

      rotten_credential =
        insert(:credential,
          schema: "oauth",
          oauth_client: nil,
          body: rotten_token,
          user: build(:user)
        )

      {:ok, fresh_credential} =
        Credentials.maybe_refresh_token(rotten_credential)

      assert fresh_credential == rotten_credential

      assert rotten_credential.body == rotten_token
      assert fresh_credential.body == rotten_token
      assert rotten_credential.body == fresh_credential.body

      assert fresh_credential.body["expires_at"] ==
               rotten_credential.body["expires_at"]
    end
  end

  describe "perform/1 with type purge_deleted" do
    setup do
      active_credential =
        insert(:credential,
          name: "Active Credential",
          body: %{foo: :bar},
          user: insert(:user)
        )

      scheduled_credential =
        insert(:credential,
          name: "Scheduled Credential",
          body: %{foo: :bar},
          user: insert(:user),
          scheduled_deletion: DateTime.utc_now()
        )

      {
        :ok,
        active_credential: active_credential,
        scheduled_credential: scheduled_credential
      }
    end

    defp mock_activity(credential) do
      insert(:step, credential: credential)
    end

    test "doesn't delete credentials that are not scheduled for deletion", %{
      active_credential: credential
    } do
      Credentials.perform(%Oban.Job{args: %{"type" => "purge_deleted"}})
      assert Repo.get(Credential, credential.id)
    end

    test "sets bodies of credentials scheduled for deletion to nil", %{
      scheduled_credential: credential
    } do
      mock_activity(credential)
      Credentials.perform(%Oban.Job{args: %{"type" => "purge_deleted"}})
      updated_credential = Repo.get(Credential, credential.id)
      assert updated_credential.body == %{}
    end

    test "doesn't set bodies of other credentials to nil", %{
      active_credential: credential
    } do
      Credentials.perform(%Oban.Job{args: %{"type" => "purge_deleted"}})
      updated_credential = Repo.get(Credential, credential.id)
      assert updated_credential.body != nil
    end

    test "doesn't delete credentials with activity in projects", %{
      scheduled_credential: credential
    } do
      mock_activity(credential)
      Credentials.perform(%Oban.Job{args: %{"type" => "purge_deleted"}})
      assert Repo.get(Credential, credential.id)
    end

    test "deletes other credentials scheduled for deletion", %{
      scheduled_credential: credential
    } do
      # This mock might be unnecessary if you want to show the credential does NOT have activity, just remove it if that's the case.
      mock_activity(credential)

      # A second scheduled credential without activity
      scheduled_credential_2 =
        insert(:credential,
          name: "Another Scheduled Credential",
          body: %{baz: :qux},
          user: insert(:user),
          scheduled_deletion: DateTime.utc_now()
        )

      Credentials.perform(%Oban.Job{args: %{"type" => "purge_deleted"}})

      assert is_nil(Repo.get(Credential, scheduled_credential_2.id))
      assert Repo.get(Credential, credential.id)
    end
  end
end
