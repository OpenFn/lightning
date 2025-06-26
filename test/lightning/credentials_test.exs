defmodule Lightning.CredentialsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Accounts.UserToken
  alias Lightning.Auditing
  alias Lightning.Credentials
  alias Lightning.Credentials.Audit
  alias Lightning.Credentials.Credential
  alias Lightning.CredentialsFixtures
  alias Lightning.Repo

  import Lightning.Factories
  import Ecto.Query
  import Mox

  import Lightning.{
    CredentialsFixtures,
    JobsFixtures
  }

  import Swoosh.TestAssertions

  setup :verify_on_exit!

  describe "Model interactions" do
    @invalid_attrs %{body: nil, name: nil}

    test "list_credentials/1 returns all credentials for given user" do
      [user_1, user_2] = insert_list(2, :user)

      credential_1 =
        insert(:credential, user_id: user_1.id, name: "a good cred")
        |> Repo.preload([:projects, :user, oauth_token: :oauth_client])

      credential_2 =
        insert(:credential, user_id: user_2.id)
        |> Repo.preload([:projects, :user, oauth_token: :oauth_client])

      credential_3 =
        insert(:credential, user_id: user_1.id, name: "better cred")
        |> Repo.preload([:projects, :user, oauth_token: :oauth_client])

      credentials = Credentials.list_credentials(user_1)

      assert credentials == [
               credential_1,
               credential_3
             ]

      names = Enum.map(credentials, & &1.name)
      assert names == Enum.sort_by(names, &String.downcase/1)

      assert Credentials.list_credentials(user_2) == [
               credential_2
             ]
    end

    test "list_credentials/1 returns all credentials for a project" do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])

      credential_1 =
        insert(:credential,
          user: user,
          name: "bbb",
          project_credentials: [%{project: project}]
        )

      credential_2 =
        insert(:credential,
          user: user,
          name: "aaa",
          project_credentials: [%{project: project}]
        )

      assert Credentials.list_credentials(project)
             |> Enum.map(fn credential -> credential.id end) == [
               credential_2.id,
               credential_1.id
             ]
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

      assert updated_credential.scheduled_deletion != nil

      assert Timex.diff(updated_credential.scheduled_deletion, now, :days) ==
               days

      retrieved_project_credentials =
        Repo.all(assoc(updated_credential, :project_credentials))

      assert Enum.empty?(retrieved_project_credentials)

      retrieved_job = Repo.reload!(job)
      assert is_nil(retrieved_job.project_credential_id)

      assert_email_sent(
        subject: "Your \"#{credential.name}\" credential will be deleted",
        to: Swoosh.Email.Recipient.format(user)
      )
    end

    test "schedule_credential_deletion/1 revokes token for oauth credentials" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      oauth_credential =
        insert(:credential,
          name: "My Credential",
          schema: "oauth",
          oauth_token:
            build(:oauth_token,
              user: user,
              oauth_client: oauth_client,
              body: %{
                "access_token" => "super_secret_access_token_123",
                "refresh_token" => "super_secret_refresh_token_123",
                "expires_in" => 3000
              }
            ),
          user: user,
          oauth_client: oauth_client
        )

      refute oauth_credential.scheduled_deletion

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, 2, fn
        env, _opts
        when env.method == :post and
               env.url == "http://example.com/oauth2/revoke" ->
          {:ok, %Tesla.Env{status: 200, body: %{}}}
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
  end

  describe "get_credential_by_project_credential/1" do
    test "returns the credential with given project_credential id" do
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

    test "succeeds with raw schema" do
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
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      # Use a proper future timestamp for expires_at
      expires_at = DateTime.to_unix(DateTime.utc_now()) + 3600

      credential =
        insert(:credential,
          name: "My Credential",
          schema: "oauth",
          oauth_token:
            build(:oauth_token,
              body: %{
                "access_token" => "ya29.a0AWY7CknfkidjXaoDTuNi",
                "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
                "expires_at" => expires_at,
                "scope" => "email calendar chat"
              },
              user: user,
              oauth_client: oauth_client
            ),
          user: user,
          oauth_client: oauth_client
        )

      update_attrs = %{
        oauth_token: %{
          "access_token" => "ya29.a0AWY7CknfkidjXaoDTuNi",
          "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
          "expires_at" => expires_at,
          "scope" => "email calendar",
          "token_type" => "Bearer"
        }
      }

      assert {:ok, %Credential{} = credential} =
               Credentials.update_credential(credential, update_attrs)

      assert credential.oauth_token.body == %{
               "access_token" => "ya29.a0AWY7CknfkidjXaoDTuNi",
               "expires_at" => expires_at,
               "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
               "scope" => "email calendar",
               "token_type" => "Bearer"
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

  describe "maybe_refresh_token/1" do
    test "doesn't refresh non OAuth credentials" do
      credential = CredentialsFixtures.credential_fixture()
      {:ok, refreshed_credential} = Credentials.maybe_refresh_token(credential)
      assert credential == refreshed_credential
    end

    test "doesn't refresh fresh OAuth credentials" do
      expires_at = DateTime.to_unix(DateTime.utc_now()) + 6 * 60

      user = insert(:user)
      oauth_client = insert(:oauth_client)

      credential =
        insert(:credential,
          schema: "oauth",
          oauth_token:
            build(:oauth_token,
              body: %{
                "access_token" => "ya29.a0AWY7CknfkidjXaoDT...",
                "expires_at" => expires_at,
                "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGA...",
                "scope" => "https://www.googleapis.com/auth/spreadsheets"
              },
              user: user,
              oauth_client: oauth_client
            ),
          user: user,
          oauth_client: oauth_client
        )

      {:ok, refreshed_credential} = Credentials.maybe_refresh_token(credential)

      assert refreshed_credential.oauth_token.body["access_token"] ==
               credential.oauth_token.body["access_token"]

      assert refreshed_credential.oauth_token.body["expires_at"] ==
               credential.oauth_token.body["expires_at"]

      assert refreshed_credential == credential
    end

    test "refreshes OAuth credentials when they are about to expire" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      credential =
        insert(:credential,
          schema: "oauth",
          oauth_token:
            build(:oauth_token,
              body: %{
                "access_token" => "ya29.a0AWY7CknfkidjXaoDTuNi",
                "expires_at" => 1000,
                "refresh_token" => "1//03dATMQTmE5NSCgYIARAAGAMSNwF",
                "scope" => "https://www.googleapis.com/auth/spreadsheets"
              },
              user: user,
              oauth_client: oauth_client
            ),
          user: user,
          oauth_client: oauth_client
        )

      new_expires_at = DateTime.to_unix(DateTime.utc_now()) + 3600

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        env, _opts
        when env.method == :post and
               env.url == oauth_client.token_endpoint ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: %{
               "access_token" => "new_access_token",
               "refresh_token" => "new_refresh_token",
               "expires_at" => new_expires_at,
               "scope" => "https://www.googleapis.com/auth/spreadsheets",
               "token_type" => "Bearer"
             }
           }}
      end)

      {:ok, refreshed_credential} = Credentials.maybe_refresh_token(credential)

      refute refreshed_credential == credential,
             "Expected credentials to be refreshed"

      assert refreshed_credential.oauth_token.body["expires_at"] ==
               new_expires_at,
             "Expected new expiry to be updated"
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

      user = insert(:user)

      rotten_credential =
        insert(:credential,
          schema: "oauth",
          oauth_client: nil,
          oauth_token:
            build(:oauth_token,
              body: rotten_token,
              oauth_client: nil,
              user: user
            ),
          user: user
        )

      {:ok, fresh_credential} =
        Credentials.maybe_refresh_token(rotten_credential)

      assert fresh_credential == rotten_credential

      assert rotten_credential.oauth_token.body == rotten_token
      assert fresh_credential.oauth_token.body == rotten_token

      assert rotten_credential.oauth_token.body ==
               fresh_credential.oauth_token.body

      assert fresh_credential.oauth_token.body["expires_at"] ==
               rotten_credential.oauth_token.body["expires_at"]
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
      mock_activity(credential)

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

  describe "credential transfers" do
    test "confirm_transfer/4 transfers credential ownership" do
      owner = insert(:user)
      receiver = insert(:user)
      credential = insert(:credential, user_id: owner.id)

      :ok = Credentials.initiate_credential_transfer(owner, receiver, credential)

      assert_email_sent(fn email ->
        [token] =
          Regex.run(~r{/transfer/[^/]+/[^/]+/([^\s\n]+)}, email.text_body,
            capture: :all_but_first
          )

        assert {:ok, updated_credential} =
                 Credentials.confirm_transfer(
                   credential.id,
                   receiver.id,
                   owner.id,
                   token
                 )

        assert updated_credential.user_id == receiver.id

        assert [audit] =
                 Repo.all(
                   from(a in Auditing.Audit, where: a.event == "transfered")
                 )

        assert audit.changes.before["user_id"] == credential.user_id
        assert audit.changes.after["user_id"] == receiver.id

        refute Repo.get_by(UserToken,
                 context: "credential_transfer",
                 user_id: owner.id
               )

        assert_email_sent(
          to: Swoosh.Email.Recipient.format(receiver),
          subject: "A credential has been transferred to you."
        )
      end)
    end

    test "confirm_transfer/4 fails with non-existent entities" do
      owner = insert(:user)
      receiver = insert(:user)
      credential = insert(:credential, user: owner)

      :ok = Credentials.initiate_credential_transfer(owner, receiver, credential)

      assert_email_sent(fn email ->
        [token] =
          Regex.run(~r{/transfer/[^/]+/[^/]+/([^\s\n]+)}, email.text_body,
            capture: :all_but_first
          )

        assert {:error, :not_found} ==
                 Credentials.confirm_transfer(
                   Ecto.UUID.generate(),
                   receiver.id,
                   owner.id,
                   token
                 )

        assert {:error, :not_found} ==
                 Credentials.confirm_transfer(
                   credential.id,
                   Ecto.UUID.generate(),
                   owner.id,
                   token
                 )
      end)
    end

    test "confirm_transfer/4 fails with invalid token" do
      owner = insert(:user)
      receiver = insert(:user)
      credential = insert(:credential)

      assert {:error, :token_error} ==
               Credentials.confirm_transfer(
                 credential.id,
                 receiver.id,
                 owner.id,
                 "invalid_token"
               )

      refreshed_credential = Repo.get!(Credential, credential.id)
      assert refreshed_credential.user_id == credential.user_id
    end

    test "initiate_credential_transfer/3 sets transfer status to pending" do
      owner = insert(:user)
      receiver = insert(:user)
      credential = insert(:credential, user_id: owner.id)

      :ok = Credentials.initiate_credential_transfer(owner, receiver, credential)

      updated_credential = Repo.get!(Credential, credential.id)
      assert updated_credential.transfer_status == :pending
    end

    test "confirm_transfer/4 updates transfer status from pending to completed" do
      owner = insert(:user)
      receiver = insert(:user)

      credential =
        insert(:credential, user_id: owner.id, transfer_status: :pending)

      :ok = Credentials.initiate_credential_transfer(owner, receiver, credential)

      assert_email_sent(fn email ->
        [token] =
          Regex.run(~r{/transfer/[^/]+/[^/]+/([^\s\n]+)}, email.text_body,
            capture: :all_but_first
          )

        {:ok, updated_credential} =
          Credentials.confirm_transfer(
            credential.id,
            receiver.id,
            owner.id,
            token
          )

        assert updated_credential.transfer_status == :completed
      end)
    end

    test "revoke_transfer/2 clears transfer status" do
      owner = insert(:user)

      credential =
        insert(:credential, user_id: owner.id, transfer_status: :pending)

      assert {:ok, updated_credential} =
               Credentials.revoke_transfer(credential.id, owner)

      assert is_nil(updated_credential.transfer_status)
    end

    test "revoke_transfer/2 clears transfer status and deletes tokens" do
      owner = insert(:user)

      credential =
        insert(:credential, user_id: owner.id, transfer_status: :pending)

      # Create a transfer token that should be deleted
      {_token_value, user_token} =
        UserToken.build_email_token(owner, "credential_transfer", owner.email)

      {:ok, _token} = Repo.insert(user_token)

      assert {:ok, updated_credential} =
               Credentials.revoke_transfer(credential.id, owner)

      assert is_nil(updated_credential.transfer_status)
      # Verify token was deleted
      refute Repo.get_by(UserToken,
               context: "credential_transfer",
               user_id: owner.id
             )
    end

    test "revoke_transfer/2 fails with non-existent credential" do
      owner = insert(:user)

      assert {:error, :not_found} =
               Credentials.revoke_transfer(Ecto.UUID.generate(), owner)
    end

    test "revoke_transfer/2 fails when user is not owner" do
      owner = insert(:user)
      other_user = insert(:user)

      credential =
        insert(:credential, user_id: owner.id, transfer_status: :pending)

      assert {:error, :not_owner} =
               Credentials.revoke_transfer(credential.id, other_user)
    end

    test "revoke_transfer/2 only works for pending transfers" do
      owner = insert(:user)

      # Test with completed status
      credential =
        insert(:credential, user_id: owner.id, transfer_status: :completed)

      assert {:error, :not_pending} =
               Credentials.revoke_transfer(credential.id, owner)

      # Test with nil status
      credential = insert(:credential, user_id: owner.id, transfer_status: nil)

      assert {:error, :not_pending} =
               Credentials.revoke_transfer(credential.id, owner)
    end

    test "confirm_transfer/4 fails if credential is not pending" do
      owner = insert(:user)
      receiver = insert(:user)

      credential =
        insert(:credential, user_id: owner.id, transfer_status: :completed)

      assert {:error, :token_error} =
               Credentials.confirm_transfer(
                 credential.id,
                 receiver.id,
                 owner.id,
                 "valid_token"
               )
    end

    test "revoke_transfer/2 fails if transfer is already completed" do
      owner = insert(:user)

      credential =
        insert(:credential, user_id: owner.id, transfer_status: :completed)

      assert {:error, :not_pending} =
               Credentials.revoke_transfer(credential.id, owner)
    end

    test "revoke_transfer/2 fails if called by an unrelated user" do
      owner = insert(:user)
      unrelated_user = insert(:user)

      credential =
        insert(:credential, user_id: owner.id, transfer_status: :pending)

      assert {:error, :not_owner} =
               Credentials.revoke_transfer(credential.id, unrelated_user)
    end
  end

  describe "validate_credential_transfer/3" do
    test "returns valid changeset when recipient exists and is not sender" do
      sender = insert(:user)
      recipient = insert(:user, email: "recipient@example.com")
      credential = insert(:credential)

      changeset = Credentials.credential_transfer_changeset(recipient.email)

      result =
        Credentials.validate_credential_transfer(changeset, sender, credential)

      assert result.valid?
    end

    test "adds error when sender tries to transfer to themselves" do
      sender = insert(:user, email: "same@example.com")
      credential = insert(:credential)

      changeset = Credentials.credential_transfer_changeset(sender.email)

      result =
        Credentials.validate_credential_transfer(changeset, sender, credential)

      assert {:email, {"You cannot transfer a credential to yourself", []}} in result.errors
    end

    test "adds error when recipient does not exist" do
      sender = insert(:user)
      credential = insert(:credential)

      changeset =
        Credentials.credential_transfer_changeset("nonexistent@example.com")

      result =
        Credentials.validate_credential_transfer(changeset, sender, credential)

      assert {:email, {"User does not exist", []}} in result.errors
    end

    test "adds error when recipient lacks access to required projects" do
      sender = insert(:user)
      recipient = insert(:user, email: "recipient@example.com")
      project = insert(:project, name: "Secret Project")

      credential =
        insert(:credential,
          project_credentials: [%{project_id: project.id}]
        )

      changeset = Credentials.credential_transfer_changeset(recipient.email)

      result =
        Credentials.validate_credential_transfer(changeset, sender, credential)

      assert {:email,
              {"User doesn't have access to these projects: Secret Project", []}} in result.errors
    end
  end

  describe "credential_transfer_changeset/1" do
    test "creates changeset with valid email" do
      changeset = Credentials.credential_transfer_changeset("test@example.com")
      assert changeset.valid?
      assert Ecto.Changeset.get_field(changeset, :email) == "test@example.com"
    end
  end

  describe "OAuth token error handling" do
    test "create_credential/1 handles failure to extract scopes from OAuth token" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      attrs = %{
        "user_id" => user.id,
        "name" => "Test OAuth Credential",
        "schema" => "oauth",
        "oauth_client_id" => oauth_client.id,
        "body" => %{"key" => "value"},
        "oauth_token" => %{
          "access_token" => "test_access_token",
          "refresh_token" => "test_refresh_token",
          "expires_in" => 3600,
          "scopex" => "read write",
          "token_type" => "Bearer"
        }
      }

      assert {:error,
              %Lightning.Credentials.OauthValidation.Error{
                type: :missing_scope,
                message: "Missing required OAuth field: scope or scopes"
              }} = Credentials.create_credential(attrs)
    end

    test "update_credential/2 handles failure to extract scopes when updating OAuth token" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      credential =
        insert(:credential,
          schema: "oauth",
          oauth_token:
            build(:oauth_token, user: user, oauth_client: oauth_client),
          user: user,
          oauth_client: oauth_client
        )

      # Test with missing scope field (scopex instead of scope)
      update_attrs = %{
        "oauth_token" => %{
          "access_token" => "new_token",
          "refresh_token" => "new_refresh_token",
          "expires_in" => 3600,
          "token_type" => "Bearer",
          # Invalid field name
          "scopex" => "read write"
        }
      }

      assert {:error,
              %Lightning.Credentials.OauthValidation.Error{
                type: :missing_scope,
                message: "Missing required OAuth field: scope or scopes"
              }} = Credentials.update_credential(credential, update_attrs)
    end
  end

  describe "transaction error handling" do
    test "handle_transaction_result/1 properly handles transaction errors" do
      user = insert(:user)

      credential = insert(:credential, user: user, name: "Original Name")

      invalid_attrs = %{"name" => nil}

      assert {:error, %Ecto.Changeset{errors: [name: {"can't be blank", _}]}} =
               Credentials.update_credential(credential, invalid_attrs)

      assert Lightning.Credentials.get_credential!(credential.id)
             |> Map.get(:name) == credential.name
    end
  end

  describe "OAuth token management" do
    test "maybe_revoke_oauth/1 handles case with nil oauth_client_id" do
      user = insert(:user)
      oauth_token = insert(:oauth_token, user: user, oauth_client: nil)

      credential =
        insert(:credential,
          schema: "oauth",
          user: user,
          oauth_token: oauth_token
        )

      {:ok, credential} = Credentials.schedule_credential_deletion(credential)

      assert credential.scheduled_deletion
    end

    test "maybe_refresh_token/1 handles OAuth client errors during refresh" do
      oauth_client = insert(:oauth_client)
      user = insert(:user)

      expired_at = DateTime.to_unix(DateTime.utc_now()) - 1000

      credential =
        insert(:credential,
          schema: "oauth",
          oauth_token:
            build(:oauth_token,
              body: %{
                "access_token" => "expired_token",
                "refresh_token" => "refresh_token",
                "expires_at" => expired_at
              },
              user: user,
              oauth_client: oauth_client
            ),
          user: user,
          oauth_client: oauth_client
        )

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        env, _opts
        when env.method == :post and
               env.url == oauth_client.token_endpoint ->
          {:error, %{status: 500, error: "Server Error", details: %{}}}
      end)

      assert {:error,
              %{status: 0, error: "unknown_error", details: %{reason: _}}} =
               Credentials.maybe_refresh_token(credential)
    end
  end

  describe "OAuth token validation" do
    test "create_credential/1 validates OAuth token data" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      # Test missing access_token
      attrs = %{
        "user_id" => user.id,
        "name" => "Test OAuth Credential",
        "schema" => "oauth",
        "oauth_client_id" => oauth_client.id,
        "body" => %{"key" => "value"},
        "oauth_token" => %{
          "refresh_token" => "test_refresh_token",
          "expires_in" => 3600,
          "scope" => "read write"
        }
      }

      assert {:error,
              %Lightning.Credentials.OauthValidation.Error{
                type: :missing_access_token,
                message: "Missing required OAuth field: access_token"
              }} = Credentials.create_credential(attrs)

      # Test missing refresh_token
      attrs = %{
        "user_id" => user.id,
        "name" => "Test OAuth Credential",
        "schema" => "oauth",
        "oauth_client_id" => oauth_client.id,
        "body" => %{"key" => "value"},
        "oauth_token" => %{
          "access_token" => "test_access_token",
          "expires_in" => 3600,
          "scope" => "read write"
        }
      }

      assert {:error,
              %Lightning.Credentials.OauthValidation.Error{
                type: :missing_refresh_token,
                message: "Missing required OAuth field: refresh_token"
              }} = Credentials.create_credential(attrs)

      # Test missing expiration fields
      attrs = %{
        "user_id" => user.id,
        "name" => "Test OAuth Credential",
        "schema" => "oauth",
        "oauth_client_id" => oauth_client.id,
        "body" => %{"key" => "value"},
        "oauth_token" => %{
          "access_token" => "test_access_token",
          "refresh_token" => "test_refresh_token",
          "scope" => "read write",
          "token_type" => "Bearer"
        }
      }

      assert {:error,
              %Lightning.Credentials.OauthValidation.Error{
                type: :missing_expiration,
                message:
                  "Missing expiration field: either expires_in or expires_at is required"
              }} = Credentials.create_credential(attrs)

      # Test valid token data
      attrs = %{
        "user_id" => user.id,
        "name" => "Test OAuth Credential",
        "schema" => "oauth",
        "oauth_client_id" => oauth_client.id,
        "body" => %{"key" => "value"},
        "oauth_token" => %{
          "access_token" => "test_access_token",
          "refresh_token" => "test_refresh_token",
          "expires_in" => 3600,
          "scope" => "read write",
          "token_type" => "Bearer"
        }
      }

      assert {:ok, _credential} = Credentials.create_credential(attrs)
    end

    test "create_credential/1 validates expected scopes" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      attrs = %{
        "user_id" => user.id,
        "name" => "Test OAuth Credential",
        "schema" => "oauth",
        "oauth_client_id" => oauth_client.id,
        "body" => %{"key" => "value"},
        "oauth_token" => %{
          "access_token" => "test_access_token",
          "refresh_token" => "test_refresh_token",
          "expires_in" => 3600,
          "scope" => "read",
          "token_type" => "Bearer"
        },
        "expected_scopes" => ["read", "write"]
      }

      assert {:error,
              %Lightning.Credentials.OauthValidation.Error{
                type: :missing_scopes,
                message: message,
                details: %{missing_scopes: ["write"]}
              }} = Credentials.create_credential(attrs)

      assert message =~ "Missing required scopes: write"
    end
  end

  describe "refresh token logic" do
    test "maybe_refresh_token/1 keeps original token when there's an oauth client error" do
      oauth_client = insert(:oauth_client)
      user = insert(:user)
      expired_at = DateTime.to_unix(DateTime.utc_now()) - 1000

      original_token = %{
        "access_token" => "original_token",
        "refresh_token" => "original_refresh",
        "expires_at" => expired_at
      }

      credential =
        insert(:credential,
          schema: "oauth",
          oauth_token:
            build(:oauth_token,
              body: original_token,
              user: user,
              oauth_client: oauth_client
            ),
          user: user,
          oauth_client: oauth_client
        )

      credential = Repo.preload(credential, oauth_token: :oauth_client)

      expect(
        Lightning.AuthProviders.OauthHTTPClient.Mock,
        :call,
        fn _env, _opts ->
          {:error, %{status: 500, error: "Network error", details: %{}}}
        end
      )

      assert {:error,
              %{status: 0, error: "unknown_error", details: %{reason: _}}} =
               Credentials.maybe_refresh_token(credential)

      reloaded =
        Repo.get!(Credential, credential.id) |> Repo.preload(:oauth_token)

      assert reloaded.oauth_token.body["access_token"] == "original_token"
      assert reloaded.oauth_token.body["expires_at"] == expired_at
    end

    test "maybe_refresh_token/1 updates token when refresh is successful" do
      oauth_client = insert(:oauth_client)
      expired_at = DateTime.to_unix(DateTime.utc_now()) - 1000

      user = insert(:user)

      credential =
        insert(:credential,
          schema: "oauth",
          oauth_token:
            build(:oauth_token,
              body: %{
                "access_token" => "expired_token",
                "refresh_token" => "refresh_token",
                "expires_at" => expired_at
              },
              user: user,
              oauth_client: oauth_client
            ),
          user: user,
          oauth_client: oauth_client
        )

      credential = Repo.preload(credential, oauth_token: :oauth_client)

      fresh_token = %{
        "access_token" => "new_token",
        "refresh_token" => "new_refresh",
        "expires_at" => DateTime.to_unix(DateTime.utc_now()) + 3600,
        "scope" => Enum.join(credential.oauth_token.scopes, " "),
        "token_type" => "Bearer"
      }

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        env, _opts
        when env.method == :post and
               env.url == oauth_client.token_endpoint ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: fresh_token
           }}
      end)

      assert {:ok, updated_credential} =
               Credentials.maybe_refresh_token(credential)

      assert updated_credential.oauth_token.body["access_token"] == "new_token"

      assert updated_credential.oauth_token.body["refresh_token"] ==
               "new_refresh"

      assert updated_credential.oauth_token.body["expires_at"] > expired_at
    end

    test "maybe_refresh_token/1 returns specific errors for different status codes" do
      oauth_client = insert(:oauth_client)
      user = insert(:user)
      expired_at = DateTime.to_unix(DateTime.utc_now()) - 1000

      credential =
        insert(:credential,
          schema: "oauth",
          oauth_token:
            build(:oauth_token,
              body: %{
                "access_token" => "expired_token",
                "refresh_token" => "refresh_token",
                "expires_at" => expired_at
              },
              user: user,
              oauth_client: oauth_client
            ),
          user: user,
          oauth_client: oauth_client
        )

      # Test 401 error
      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        _env, _opts ->
          {:ok,
           %Tesla.Env{
             status: 401,
             body: %{"error" => "invalid_token"}
           }}
      end)

      assert {:error, :reauthorization_required} =
               Credentials.maybe_refresh_token(credential)

      # Test 429 error
      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        _env, _opts ->
          {:ok,
           %Tesla.Env{
             status: 429,
             body: %{"error" => "rate_limit_exceeded"}
           }}
      end)

      assert {:error, :temporary_failure} =
               Credentials.maybe_refresh_token(credential)

      # Test 503 error
      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        _env, _opts ->
          {:ok,
           %Tesla.Env{
             status: 503,
             body: %{"error" => "service_unavailable"}
           }}
      end)

      assert {:error, :temporary_failure} =
               Credentials.maybe_refresh_token(credential)
    end
  end

  describe "OAuth token creation with scope matching" do
    test "create_credential/1 validates token_type field" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      attrs = %{
        "user_id" => user.id,
        "name" => "Test OAuth Credential",
        "schema" => "oauth",
        "oauth_client_id" => oauth_client.id,
        "body" => %{"key" => "value"},
        "oauth_token" => %{
          "access_token" => "test_access_token",
          "refresh_token" => "test_refresh_token",
          "expires_in" => 3600,
          "scope" => "read write",
          "token_type" => "Basic"
        }
      }

      assert {:error,
              %Lightning.Credentials.OauthValidation.Error{
                type: :unsupported_token_type,
                message: "Unsupported token type: 'Basic'. Expected 'Bearer'"
              }} = Credentials.create_credential(attrs)
    end

    test "update_credential/2 preserves refresh_token when not provided in update" do
      user = insert(:user)
      oauth_client = insert(:oauth_client)

      credential =
        insert(:credential,
          schema: "oauth",
          oauth_token:
            build(:oauth_token,
              body: %{
                "access_token" => "old_token",
                "refresh_token" => "existing_refresh",
                "expires_in" => 3600,
                "scope" => "read write",
                "token_type" => "Bearer"
              },
              user: user,
              oauth_client: oauth_client
            ),
          user: user,
          oauth_client: oauth_client
        )

      update_attrs = %{
        "oauth_token" => %{
          "access_token" => "new_token",
          "expires_in" => 7200,
          "scope" => "read write",
          "token_type" => "Bearer"
        }
      }

      assert {:ok, updated_credential} =
               Credentials.update_credential(credential, update_attrs)

      assert updated_credential.oauth_token.body["refresh_token"] ==
               "existing_refresh"
    end
  end

  describe "list_user_credentials_in_project/2" do
    test "returns all credentials owned by a user that are used in a project" do
      user_1 = insert(:user)
      user_2 = insert(:user)

      project = insert(:project)

      credential_1 =
        insert(:credential,
          user: user_1,
          name: "cred A",
          project_credentials: [%{project: project}]
        )

      credential_2 =
        insert(:credential,
          user: user_1,
          name: "cred B",
          project_credentials: [%{project: project}]
        )

      _credential_3 = insert(:credential, user: user_1, name: "cred C")

      credential_4 =
        insert(:credential,
          user: user_2,
          name: "cred D",
          project_credentials: [%{project: project}]
        )

      user_1_credentials =
        Credentials.list_user_credentials_in_project(user_1, project)

      assert length(user_1_credentials) == 2

      assert Enum.map(user_1_credentials, & &1.id) |> Enum.sort() ==
               [credential_1.id, credential_2.id] |> Enum.sort()

      user_2_credentials =
        Credentials.list_user_credentials_in_project(user_2, project)

      assert length(user_2_credentials) == 1
      assert Enum.map(user_2_credentials, & &1.id) == [credential_4.id]

      user_1_credential_names = Enum.map(user_1_credentials, & &1.name)
      assert "cred A" in user_1_credential_names
      assert "cred B" in user_1_credential_names
      assert length(user_1_credential_names) == 2
    end

    test "returns empty list when user has no credentials in project" do
      user = insert(:user)
      project = insert(:project)

      insert(:credential, user: user)

      credentials = Credentials.list_user_credentials_in_project(user, project)
      assert Enum.empty?(credentials)
    end
  end
end
