defmodule LightningWeb.CredentialLive.IndexTest do
  use LightningWeb.ConnCase, async: false

  import Lightning.AdaptorTestHelpers
  import Lightning.Factories
  import Phoenix.LiveViewTest
  import LightningWeb.CredentialPageHelpers

  alias Lightning.Credentials
  alias Lightning.Credentials.Credential
  alias Lightning.Credentials.OauthClient
  alias Lightning.Repo
  alias LightningWeb.CredentialPageHelpers

  # The page is drawn by React from data-props. What it renders from them
  # is tested in the design system's own CredentialsIndexPage and
  # CredentialIndex tests (in @openfn/ui), and the events it sends in
  # assets/test/design-system/CredentialsIndexPage.test.tsx.

  @refused CredentialPageHelpers.refused()

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "the list" do
    test "sends the viewer's own credentials and OAuth clients, without secrets",
         %{conn: conn, user: user, project: project} do
      credential =
        credential_with_body(user, %{
          name: "dhis2 prod",
          schema: "@openfn/language-dhis2"
        })

      insert(:credential_body,
        credential: credential,
        name: "staging",
        body: %{"a" => "s"}
      )

      insert(:project_credential, credential: credential, project: project)
      credential_with_body(insert(:user), %{name: "someone else's"})
      client = insert(:oauth_client, user: user, name: "my client")
      insert(:oauth_client, name: "another's global", global: true)

      view = open(conn)

      assert %{
               "credentials" => [row],
               "oauthClients" => clients,
               "projects" => [%{"id" => project_id}],
               "oauthSignIns" => [],
               "canCreateGlobalOauthClient" => false
             } = props(view)

      assert project_id == project.id

      assert %{
               "id" => id,
               "schema" => "dhis2",
               "environments" => ["main", "staging"],
               "projects" => [%{"name" => _, "workflowsUsing" => []}],
               "canEdit" => true,
               "scheduledDeletion" => nil,
               "hasActivityInProjects" => false
             } = row

      assert id == credential.id

      assert [
               %{
                 "name" => "another's global",
                 "global" => true,
                 "canEdit" => false
               },
               %{"id" => client_id, "name" => "my client", "canEdit" => true}
             ] = clients

      assert client_id == client.id
      refute render(view) =~ "secret-a"
      refute render(view) =~ client.client_secret
    end

    test "names, for each credential, only the workflows using it",
         %{conn: conn, user: user, project: project} do
      used = credential_with_body(user, %{name: "used"})
      unused = credential_with_body(user, %{name: "unused"})

      used_here =
        insert(:project_credential, credential: used, project: project)

      insert(:project_credential, credential: unused, project: project)

      insert(:simple_workflow, project: project, name: "uses it")
      |> Map.fetch!(:jobs)
      |> hd()
      |> Ecto.Changeset.change(project_credential_id: used_here.id)
      |> Repo.update!()

      rows = Map.new(props(open(conn))["credentials"], &{&1["name"], &1})

      assert [%{"workflowsUsing" => ["uses it"]}] = rows["used"]["projects"]
      assert [%{"workflowsUsing" => []}] = rows["unused"]["projects"]
    end

    test "shows a global client someone else owns as global only",
         %{conn: conn} do
      owner = insert(:user)

      insert(:project_oauth_client,
        project: build(:project, name: "elsewhere"),
        oauth_client:
          build(:oauth_client, user: owner, name: "shared global", global: true)
      )

      view = open(conn)

      assert [%{"global" => true, "projects" => [], "ownerEmail" => ""}] =
               props(view)["oauthClients"]

      refute render(view) =~ "elsewhere"
      refute render(view) =~ owner.email
    end
  end

  describe "create_credential" do
    test "creates a raw credential shared with the viewer's project",
         %{conn: conn, user: user, project: project} do
      view = open(conn)

      assert send_event(
               view,
               "create_credential",
               raw_values(%{"projectIds" => [project.id]})
             ) =~
               "Credential created successfully"

      assert [credential] = Credentials.list_credentials(user)
      assert credential.name == "My raw"
      assert Enum.map(credential.projects, & &1.id) == [project.id]
      assert bodies(credential) == %{"main" => %{"a" => 1}}
      assert [%{"name" => "My raw"}] = props(view)["credentials"]
    end

    test "doesn't share it with a project the viewer isn't in",
         %{conn: conn, user: user} do
      other_project = insert(:project)
      view = open(conn)

      send_event(
        view,
        "create_credential",
        raw_values(%{"projectIds" => [other_project.id]})
      )

      assert [%{projects: []}] = Credentials.list_credentials(user)
    end

    test "replies with the name's error", %{conn: conn, user: user} do
      view = open(conn)

      send_event(view, "create_credential", raw_values(%{"name" => ""}))

      assert_reply(view, %{error: _, fieldErrors: %{"name" => [_]}})
      assert Credentials.list_credentials(user) == []
    end

    test "replies with an environment's error for a body that isn't JSON",
         %{conn: conn, user: user} do
      view = open(conn)

      env = %{
        "name" => "main",
        "previousName" => nil,
        "body" => "{nope",
        "signInId" => nil
      }

      send_event(
        view,
        "create_credential",
        raw_values(%{"environments" => [env]})
      )

      assert_reply(view, %{
        fieldErrors: %{"environments.main" => ["Invalid JSON format"]}
      })

      assert Credentials.list_credentials(user) == []
    end

    test "refuses an OAuth credential without a sign-in", %{
      conn: conn,
      user: user
    } do
      client = insert(:oauth_client, user: user)
      view = open(conn)

      env = %{
        "name" => "main",
        "previousName" => nil,
        "body" => "",
        "signInId" => "s1"
      }

      send_event(
        view,
        "create_credential",
        raw_values(%{
          "schema" => "oauth",
          "oauthClientId" => client.id,
          "environments" => [env]
        })
      )

      assert_reply(view, %{fieldErrors: %{"environments.main" => [_]}})
      assert Credentials.list_credentials(user) == []
    end
  end

  describe "update_credential" do
    test "saves every environment, renames and deletes", %{
      conn: conn,
      user: user
    } do
      credential = credential_with_body(user, %{name: "raw one"})

      insert(:credential_body,
        credential: credential,
        name: "staging",
        body: %{"s" => 1}
      )

      insert(:credential_body,
        credential: credential,
        name: "old",
        body: %{"o" => 1}
      )

      view = open(conn)

      envs = [
        %{
          "name" => "main",
          "previousName" => "main",
          "body" => ~s({"a": 2}),
          "signInId" => nil
        },
        %{
          "name" => "prod",
          "previousName" => "staging",
          "body" => ~s({"s": 2}),
          "signInId" => nil
        }
      ]

      assert send_event(
               view,
               "update_credential",
               raw_values(%{
                 "id" => credential.id,
                 "name" => "renamed",
                 "environments" => envs
               })
             ) =~ "Credential updated successfully"

      assert Repo.reload!(credential).name == "renamed"

      assert bodies(credential) == %{
               "main" => %{"a" => 2},
               "prod" => %{"s" => 2}
             }
    end

    test "refuses someone else's credential", %{conn: conn} do
      other = credential_with_body(insert(:user), %{name: "theirs"})
      view = open(conn)

      send_event(
        view,
        "update_credential",
        raw_values(%{"id" => other.id, "name" => "mine now"})
      )

      assert_reply(view, %{error: @refused})
      assert Repo.reload!(other).name == "theirs"
      assert bodies(other) == %{"main" => %{"a" => "secret-a"}}
    end

    test "keeps a project the viewer can't see, and removes one left out",
         %{conn: conn, user: user, project: project} do
      credential = credential_with_body(user)
      hidden = insert(:project)
      insert(:project_credential, credential: credential, project: hidden)
      insert(:project_credential, credential: credential, project: project)
      view = open(conn)

      send_event(
        view,
        "update_credential",
        raw_values(%{"id" => credential.id, "projectIds" => [hidden.id]})
      )

      assert [%{id: hidden_id}] =
               Repo.preload(credential, :projects, force: true).projects

      assert hidden_id == hidden.id
    end
  end

  describe "load_credential_secrets" do
    test "answers with the stored environments", %{conn: conn, user: user} do
      credential = credential_with_body(user)
      view = open(conn)

      send_event(view, "load_credential_secrets", %{"id" => credential.id})

      assert_reply(view, %{
        environments: [%{name: "main", body: body, oauth: nil}]
      })

      assert Jason.decode!(body) == %{"a" => "secret-a"}
    end

    test "opens one without stored values on an empty main", %{
      conn: conn,
      user: user
    } do
      credential = insert(:credential, user: user)
      view = open(conn)

      send_event(view, "load_credential_secrets", %{"id" => credential.id})

      assert_reply(view, %{environments: [%{name: "main", body: "{}"}]})
    end

    test "refuses someone else's credential", %{conn: conn} do
      other = credential_with_body(insert(:user))
      view = open(conn)

      send_event(view, "load_credential_secrets", %{"id" => other.id})

      assert_reply(view, %{error: @refused})
    end
  end

  describe "load_credential_schema" do
    setup :isolated_adaptors

    setup do
      seed_all_credential_schemas()
      :ok
    end

    test "answers with the adaptor's fields", %{conn: conn} do
      view = open(conn)

      send_event(view, "load_credential_schema", %{"key" => "dhis2"})

      assert_reply(view, %{fields: fields})

      assert %{
               "username" => %{kind: "text", required: true, label: "Username"},
               "password" => %{kind: "password"},
               "hostUrl" => %{kind: "url"},
               "apiVersion" => %{kind: "text", placeholder: "35"}
             } = Map.new(fields, &{&1.key, &1})
    end

    test "offers the adaptors with a credential schema", %{conn: conn} do
      assert %{"key" => "dhis2", "name" => "dhis2"} in props(open(conn))[
               "credentialTypes"
             ]
    end
  end

  describe "delete_credential" do
    test "schedules the deletion", %{conn: conn, user: user} do
      credential = credential_with_body(user)
      view = open(conn)

      assert send_event(view, "delete_credential", %{
               "id" => credential.id,
               "now" => false
             }) =~
               "Credential scheduled for deletion"

      assert Repo.reload!(credential).scheduled_deletion
      assert [%{"scheduledDeletion" => when_}] = props(view)["credentials"]
      assert when_
    end

    test "deletes a scheduled one now", %{conn: conn, user: user} do
      credential =
        credential_with_body(user, %{scheduled_deletion: DateTime.utc_now()})

      view = open(conn)

      assert send_event(view, "delete_credential", %{
               "id" => credential.id,
               "now" => true
             }) =~
               "Credential deleted successfully"

      refute Repo.get(Credential, credential.id)
    end

    test "won't delete now one that isn't scheduled", %{conn: conn, user: user} do
      credential = credential_with_body(user)
      view = open(conn)

      send_event(view, "delete_credential", %{
        "id" => credential.id,
        "now" => true
      })

      assert_reply(view, %{error: "You can't perform this action"})
      assert Repo.get(Credential, credential.id)
    end

    test "won't delete now one used in runs", %{conn: conn, user: user} do
      credential =
        credential_with_body(user, %{scheduled_deletion: DateTime.utc_now()})

      insert(:step, credential: credential)
      view = open(conn)

      send_event(view, "delete_credential", %{
        "id" => credential.id,
        "now" => true
      })

      assert_reply(view, %{
        error: "Cannot delete a credential that has activities in projects"
      })

      assert Repo.get(Credential, credential.id)
    end

    test "refuses someone else's credential", %{conn: conn} do
      other = credential_with_body(insert(:user))
      view = open(conn)

      send_event(view, "delete_credential", %{"id" => other.id, "now" => false})

      assert_reply(view, %{error: @refused})
      refute Repo.reload!(other).scheduled_deletion
    end
  end

  describe "cancel_credential_deletion" do
    test "restores a scheduled credential", %{conn: conn, user: user} do
      credential =
        credential_with_body(user, %{scheduled_deletion: DateTime.utc_now()})

      view = open(conn)

      assert send_event(view, "cancel_credential_deletion", %{
               "id" => credential.id
             }) =~
               "Credential deletion canceled"

      refute Repo.reload!(credential).scheduled_deletion
    end

    test "refuses someone else's credential", %{conn: conn} do
      other =
        credential_with_body(insert(:user), %{
          scheduled_deletion: DateTime.utc_now()
        })

      view = open(conn)

      send_event(view, "cancel_credential_deletion", %{"id" => other.id})

      assert_reply(view, %{error: @refused})
      assert Repo.reload!(other).scheduled_deletion
    end
  end

  describe "transfers" do
    test "starts a transfer to another user", %{conn: conn, user: user} do
      credential = credential_with_body(user)
      receiver = insert(:user)
      view = open(conn)

      assert send_event(view, "transfer_credential", %{
               "id" => credential.id,
               "receiverEmail" => receiver.email
             }) =~ "Credential transfer initiated"

      assert Repo.reload!(credential).transfer_status == :pending
      assert [%{"transferStatus" => "pending"}] = props(view)["credentials"]

      assert send_event(view, "revoke_credential_transfer", %{
               "id" => credential.id
             }) =~
               "Transfer revoked successfully"

      refute Repo.reload!(credential).transfer_status
    end

    test "replies with the email's error", %{conn: conn, user: user} do
      credential = credential_with_body(user)
      view = open(conn)

      send_event(view, "transfer_credential", %{
        "id" => credential.id,
        "receiverEmail" => user.email
      })

      assert_reply(view, %{fieldErrors: %{"receiverEmail" => [_]}})
      refute Repo.reload!(credential).transfer_status
    end

    test "refuses someone else's credential", %{conn: conn} do
      other = credential_with_body(insert(:user))
      view = open(conn)

      send_event(view, "transfer_credential", %{
        "id" => other.id,
        "receiverEmail" => insert(:user).email
      })

      assert_reply(view, %{error: @refused})
      refute Repo.reload!(other).transfer_status

      other |> Ecto.Changeset.change(transfer_status: :pending) |> Repo.update!()
      send_event(view, "revoke_credential_transfer", %{"id" => other.id})

      assert_reply(view, %{error: @refused})
      assert Repo.reload!(other).transfer_status == :pending
    end
  end

  describe "OAuth clients" do
    test "creates, edits, answers with its secrets and deletes the viewer's own",
         %{conn: conn, project: project} do
      view = open(conn)

      assert send_event(
               view,
               "create_oauth_client",
               client_values(%{"projectIds" => [project.id], "global" => true})
             ) =~ "Oauth client created successfully"

      assert [client] = Repo.all(OauthClient)
      # Only a superuser may make a client global.
      refute client.global
      assert client.mandatory_scopes == "read"

      assert [%{"name" => "My client", "projects" => [_]}] =
               props(view)["oauthClients"]

      send_event(view, "load_oauth_client_secrets", %{"id" => client.id})
      assert_reply(view, %{clientId: "the-id", clientSecret: "the-secret"})

      assert send_event(
               view,
               "update_oauth_client",
               client_values(%{"id" => client.id, "name" => "Renamed"})
             ) =~ "Oauth client updated successfully"

      assert Repo.reload!(client).name == "Renamed"

      assert send_event(view, "delete_oauth_client", %{"id" => client.id}) =~
               "Oauth client deleted"

      refute Repo.get(OauthClient, client.id)
    end

    test "a superuser may make one global", %{conn: conn, user: user} do
      user |> Ecto.Changeset.change(role: :superuser) |> Repo.update!()
      view = open(conn)

      assert props(view)["canCreateGlobalOauthClient"]
      send_event(view, "create_oauth_client", client_values(%{"global" => true}))

      assert [%{global: true}] = Repo.all(OauthClient)
    end

    test "refuses another user's global client", %{conn: conn} do
      client = insert(:oauth_client, global: true, name: "theirs")
      view = open(conn)

      for {event, payload} <- [
            {"update_oauth_client", client_values(%{"id" => client.id})},
            {"load_oauth_client_secrets", %{"id" => client.id}},
            {"delete_oauth_client", %{"id" => client.id}}
          ] do
        send_event(view, event, payload)
        assert_reply(view, %{error: @refused})
      end

      assert %{name: "theirs"} = Repo.reload!(client)
    end

    test "replies with field errors", %{conn: conn} do
      view = open(conn)

      send_event(
        view,
        "create_oauth_client",
        client_values(%{"tokenEndpoint" => ""})
      )

      assert_reply(view, %{fieldErrors: %{"tokenEndpoint" => [_]}})
      assert Repo.all(OauthClient) == []
    end
  end

  describe "OAuth sign-in" do
    @token CredentialPageHelpers.token()

    setup %{user: user} do
      %{client: insert(:oauth_client, user: user)}
    end

    test "the form that started it saves its token, which never reaches the page",
         %{conn: conn, user: user, client: client} do
      stub_provider(client)
      view = open(conn)
      sign_in(view, client)

      assert [
               %{
                 "signInId" => "s1",
                 "error" => nil,
                 "userInfo" => %{"name" => "Ada", "email" => "ada@x.org"}
               }
             ] = props(view)["oauthSignIns"]

      refute render(view) =~ "the-access-token"

      send_event(view, "create_credential", oauth_values(client, "s1"))
      assert_reply(view, %{})

      assert [credential] = Credentials.list_credentials(user)
      assert credential.oauth_client_id == client.id

      assert %{"main" => %{"access_token" => "the-access-token"}} =
               bodies(credential)

      assert props(view)["oauthSignIns"] == []
    end

    test "an edit takes a sign-in for that credential", %{
      conn: conn,
      user: user,
      client: client
    } do
      credential =
        credential_with_body(
          user,
          %{schema: "oauth", oauth_client: client},
          %{"access_token" => "old"}
        )

      stub_provider(client)
      view = open(conn)
      sign_in(view, client, %{"credentialId" => credential.id})

      send_event(
        view,
        "update_credential",
        oauth_values(client, "s1", %{"id" => credential.id})
      )

      assert_reply(view, %{})

      assert %{"main" => %{"access_token" => "the-access-token"}} =
               bodies(credential)
    end

    test "refuses a sign-in for another form, named twice, or used already",
         %{conn: conn, user: user, client: client} do
      stub_provider(client)
      view = open(conn)
      sign_in(view, client)

      send_event(
        view,
        "create_credential",
        oauth_values(client, "s1", %{"formId" => "form-2"})
      )

      assert_reply(view, %{fieldErrors: %{"environments.main" => [_]}})

      twice = %{
        "name" => "staging",
        "previousName" => nil,
        "body" => "",
        "signInId" => "s1"
      }

      values = oauth_values(client, "s1")

      send_event(
        view,
        "create_credential",
        %{values | "environments" => values["environments"] ++ [twice]}
      )

      assert_reply(view, %{fieldErrors: %{"environments.main" => [_]}})
      assert Credentials.list_credentials(user) == []

      send_event(view, "create_credential", values)
      assert_reply(view, %{})

      send_event(view, "create_credential", %{values | "name" => "again"})
      assert_reply(view, %{fieldErrors: %{"environments.main" => [_]}})
      assert [_one] = Credentials.list_credentials(user)
    end

    test "a sign-in for a new credential can't be saved onto an existing one",
         %{conn: conn, user: user, client: client} do
      credential =
        credential_with_body(
          user,
          %{schema: "oauth", oauth_client: client},
          %{"access_token" => "old"}
        )

      stub_provider(client)
      view = open(conn)
      sign_in(view, client)

      send_event(
        view,
        "update_credential",
        oauth_values(client, "s1", %{"id" => credential.id})
      )

      assert_reply(view, %{fieldErrors: %{"environments.main" => [_]}})
      assert %{"main" => %{"access_token" => "old"}} = bodies(credential)
    end

    test "tells the page when the provider turns the sign-in down", %{
      conn: conn,
      client: client
    } do
      view = open(conn)
      sign_in(view, client, %{}, %{error: "access_denied"})

      assert [%{"signInId" => "s1", "error" => error, "userInfo" => nil}] =
               props(view)["oauthSignIns"]

      assert is_binary(error)
    end

    test "tells the page when the token doesn't grant the scopes asked for", %{
      conn: conn,
      client: client
    } do
      stub_provider(client, {200, %{@token | "scope" => "scope_1"}})
      view = open(conn)
      sign_in(view, client)

      assert [%{"error" => error}] = props(view)["oauthSignIns"]
      assert is_binary(error)

      send_event(view, "create_credential", oauth_values(client, "s1"))
      assert_reply(view, %{fieldErrors: %{"environments.main" => [_]}})
    end

    test "a discarded form's sign-ins can't be saved", %{
      conn: conn,
      client: client
    } do
      stub_provider(client)
      view = open(conn)
      sign_in(view, client)

      send_event(view, "discard_oauth_sign_ins", %{"formId" => "form-1"})
      assert_reply(view, %{})
      assert props(view)["oauthSignIns"] == []

      send_event(view, "create_credential", oauth_values(client, "s1"))
      assert_reply(view, %{fieldErrors: %{"environments.main" => [_]}})
    end

    test "refuses another user's client, their credential, or another client's credential",
         %{conn: conn, user: user, client: client} do
      view = open(conn)

      start = fn attrs ->
        send_event(
          view,
          "authorize_oauth",
          Map.merge(
            %{
              "formId" => "form-1",
              "signInId" => "s-#{System.unique_integer([:positive])}",
              "credentialId" => nil,
              "oauthClientId" => client.id,
              "scopes" => [],
              "environment" => "main"
            },
            attrs
          )
        )
      end

      start.(%{"oauthClientId" => insert(:oauth_client).id})
      assert_reply(view, %{error: @refused})

      theirs = insert(:credential, schema: "oauth", oauth_client: client)
      start.(%{"credentialId" => theirs.id})
      assert_reply(view, %{error: @refused})

      other_client = insert(:oauth_client, user: user)

      mine =
        insert(:credential,
          user: user,
          schema: "oauth",
          oauth_client: other_client
        )

      start.(%{"credentialId" => mine.id})
      assert_reply(view, %{error: @refused})
    end

    test "the edit form gets the stored token's scopes and who signed in, not the token",
         %{conn: conn, user: user, client: client} do
      credential =
        credential_with_body(
          user,
          %{schema: "oauth", oauth_client: client},
          Map.put(@token, "expires_at", System.os_time(:second) + 3600)
        )

      stub_provider(client)
      view = open(conn)

      send_event(view, "load_credential_secrets", %{"id" => credential.id})

      assert_reply(view, %{
        environments: [
          %{
            name: "main",
            body: "",
            oauth: %{
              scopes: ["scope_1", "scope_2"],
              status: "ready",
              userInfo: %{name: "Ada", email: "ada@x.org"}
            }
          }
        ]
      })
    end

    test "a renamed environment keeps the token stored under its old name",
         %{conn: conn, user: user, client: client} do
      credential =
        credential_with_body(
          user,
          %{schema: "oauth", oauth_client: client},
          @token
        )

      view = open(conn)

      send_event(
        view,
        "update_credential",
        oauth_values(client, nil, %{
          "id" => credential.id,
          "environments" => [
            %{
              "name" => "production",
              "previousName" => "main",
              "body" => "",
              "signInId" => nil
            }
          ]
        })
      )

      assert_reply(view, %{})
      assert bodies(credential) == %{"production" => @token}
    end

    test "replies with why a stored token can't be saved",
         %{conn: conn, user: user, client: client} do
      credential =
        credential_with_body(
          user,
          %{schema: "oauth", oauth_client: client},
          Map.delete(@token, "scope")
        )

      view = open(conn)

      send_event(
        view,
        "update_credential",
        oauth_values(client, nil, %{
          "id" => credential.id,
          "name" => "renamed",
          "environments" => [
            %{
              "name" => "main",
              "previousName" => "main",
              "body" => "",
              "signInId" => nil
            }
          ]
        })
      )

      assert_reply(view, %{error: error})
      refute error =~ "Something went wrong"
    end

    test "an expired token the provider won't refresh needs signing in again",
         %{conn: conn, user: user, client: client} do
      credential =
        credential_with_body(
          user,
          %{schema: "oauth", oauth_client: client},
          Map.put(@token, "expires_at", System.os_time(:second) - 60)
        )

      stub_provider(client, {400, %{"error" => "invalid_grant"}})
      view = open(conn)

      send_event(view, "load_credential_secrets", %{"id" => credential.id})

      assert_reply(view, %{
        environments: [%{oauth: %{status: "reauthorize", userInfo: nil}}]
      })
    end
  end

  test "refuses an unknown event, or one with the wrong shape", %{conn: conn} do
    view = open(conn)

    send_event(view, "delete_everything", %{})
    assert_reply(view, %{error: @refused})

    send_event(view, "load_credential_schema", %{"key" => 1})
    assert_reply(view, %{error: @refused})
  end
end
