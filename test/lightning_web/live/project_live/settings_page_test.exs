defmodule LightningWeb.ProjectLive.SettingsPageTest do
  use LightningWeb.ConnCase, async: true
  use Mimic

  import Lightning.Factories
  import LightningWeb.ProjectSettingsPageHelpers
  import Phoenix.Component, only: [sigil_H: 2]
  import Phoenix.LiveViewTest

  import LightningWeb.CredentialPageHelpers,
    only: [raw_values: 1, client_values: 1, stub_provider: 1]

  alias Lightning.Accounts.User
  alias Lightning.Collections
  alias Lightning.Credentials
  alias Lightning.Credentials.OauthClient
  alias Lightning.Projects.ProjectUser
  alias Lightning.Repo

  # The page is drawn by React from data-props. What it draws from them is
  # tested in the design system's own ProjectSettingsPage.test.tsx (in
  # @openfn/ui), and the events it sends in
  # assets/test/design-system/ProjectSettingsPage.test.tsx. These tests
  # check the props and that the server answers each event, refusals too.

  setup_all do
    Mimic.copy(Phoenix.Router)
    :ok
  end

  setup :register_and_log_in_user

  defp project_with(user, role, attrs \\ []) do
    insert(
      :project,
      Keyword.merge([project_users: [%{user: user, role: role}]], attrs)
    )
  end

  describe "props" do
    test "every tab's data matches the page's Props type", %{
      conn: conn,
      user: user
    } do
      project =
        project_with(user, :owner,
          name: "my-project",
          description: "about it",
          concurrency: 1
        )

      insert(:collection, project: project, name: "things")
      insert(:webhook_auth_method, project: project, name: "basic one")

      props = conn |> open(project) |> props()

      assert %{
               "project" => %{"id" => id, "parentId" => nil},
               "parent" => nil,
               "deleting" => false,
               "setup" => %{
                 "name" => "my-project",
                 "description" => "about it",
                 "concurrency" => 1,
                 "canEditProject" => true,
                 "canDeleteProject" => true,
                 "sandboxDeletion" => nil
               },
               "collections" => %{"collections" => [%{"name" => "things"}]},
               "webhookSecurity" => %{
                 "authMethods" => [%{"name" => "basic one"}]
               },
               "collaboration" => %{
                 "collaborators" => [%{"isCurrentUser" => true}]
               }
             } = props

      assert id == project.id
    end

    test "a viewer is told they can't edit or delete", %{
      conn: conn,
      user: user
    } do
      project = project_with(user, :viewer)

      assert %{"canEditProject" => false, "canDeleteProject" => false} =
               conn |> open(project) |> props() |> Map.fetch!("setup")
    end

    test "a sandbox names its parent and what deleting it takes along", %{
      conn: conn,
      user: user
    } do
      parent = project_with(user, :owner, name: "root")
      sandbox = project_with(user, :owner, name: "sb", parent: parent)
      project_with(user, :owner, name: "child", parent: sandbox)

      props = conn |> open(sandbox) |> props()

      assert props["parent"] == %{
               "name" => "root",
               "settingsHref" => "/projects/#{parent.id}/settings"
             }

      assert props["setup"]["sandboxDeletion"] == %{
               "rootName" => "root",
               "descendantCount" => 1
             }
    end
  end

  describe "save_identity" do
    test "saves the name as typed, made URL-safe, and the description", %{
      conn: conn,
      user: user
    } do
      project = project_with(user, :admin)
      view = open(conn, project)

      send_event(view, "save_identity", %{
        "rawName" => "My New Name",
        "description" => "new words"
      })

      assert render(view) =~ "Project updated successfully"

      assert %{name: "my-new-name", description: "new words"} =
               Repo.reload(project)

      assert %{"name" => "my-new-name"} = props(view)["setup"]
    end

    test "saves only the name and description", %{conn: conn, user: user} do
      project = project_with(user, :admin)
      view = open(conn, project)

      send_event(view, "save_identity", %{
        "rawName" => "renamed",
        "requires_mfa" => true,
        "requiresMfa" => true,
        "retentionPolicy" => "erase_all"
      })

      assert %{
               name: "renamed",
               requires_mfa: false,
               retention_policy: :retain_all
             } =
               Repo.reload(project)
    end

    test "answers a bad name with its field error", %{conn: conn, user: user} do
      project = project_with(user, :admin)
      view = open(conn, project)

      send_event(view, "save_identity", %{"rawName" => ""})

      assert_reply(view, %{fieldErrors: %{"rawName" => [_ | _]}})
      assert Repo.reload(project).name == project.name
    end

    for role <- [:editor, :viewer] do
      test "refuses #{role}s", %{conn: conn, user: user} do
        project = project_with(user, unquote(role))
        view = open(conn, project)

        send_event(view, "save_identity", %{"rawName" => "taken-over"})

        assert_refused(view)

        assert Repo.reload(project).name == project.name
      end
    end
  end

  describe "save_concurrency" do
    test "sets one run at a time, then parallel again", %{
      conn: conn,
      user: user
    } do
      project = project_with(user, :admin)
      view = open(conn, project)

      send_event(view, "save_concurrency", %{"concurrency" => 1})
      assert_ok(view)
      assert Repo.reload(project).concurrency == 1

      send_event(view, "save_concurrency", %{"concurrency" => nil})
      assert_ok(view)
      assert Repo.reload(project).concurrency == nil
    end

    test "refuses a viewer", %{conn: conn, user: user} do
      project = project_with(user, :viewer)
      view = open(conn, project)

      send_event(view, "save_concurrency", %{"concurrency" => 1})

      assert_refused(view)

      assert Repo.reload(project).concurrency == nil
    end
  end

  describe "the deletion modal" do
    test "opens on the delete route for an owner", %{conn: conn, user: user} do
      project = project_with(user, :owner)

      assert %{"deleting" => true} =
               conn |> open(project, "settings/delete") |> props()
    end

    test "schedules the project when the name matches", %{
      conn: conn,
      user: user
    } do
      project = project_with(user, :owner, name: "doomed")
      view = open(conn, project, "settings/delete")

      send_event(view, "delete_project", %{"nameConfirmation" => "doomed"})

      assert_redirect(view, ~p"/projects")
      assert Repo.reload(project).scheduled_deletion
    end

    test "refuses a name that doesn't match", %{conn: conn, user: user} do
      project = project_with(user, :owner, name: "doomed")
      view = open(conn, project, "settings/delete")

      send_event(view, "delete_project", %{"nameConfirmation" => "other"})

      assert_reply(view, %{error: "doesn't match the project name"})
      refute Repo.reload(project).scheduled_deletion
    end

    for role <- [:admin, :editor, :viewer] do
      test "refuses #{role}s", %{conn: conn, user: user} do
        project = project_with(user, unquote(role), name: "doomed")
        view = open(conn, project)

        send_event(view, "delete_project", %{"nameConfirmation" => "doomed"})

        assert_refused(view)
        refute Repo.reload(project).scheduled_deletion
      end
    end

    test "refuses a sandbox's editor", %{conn: conn, user: user} do
      parent = project_with(user, :editor)
      sandbox = project_with(user, :editor, name: "sb", parent: parent)
      view = open(conn, sandbox)

      send_event(view, "delete_project", %{"nameConfirmation" => "sb"})

      assert_refused(view)
      assert Repo.reload(sandbox)
    end
  end

  # The hosted concurrency form still submits the old "save".
  test "the old save refuses a viewer", %{conn: conn, user: user} do
    project = project_with(user, :viewer)
    view = open(conn, project)

    render_hook(view, "save", %{"project" => %{"concurrency" => 1}})

    assert Repo.reload(project).concurrency == nil
  end

  # The credential index's own events are tested on the user's Credentials
  # page (credential_live/index_test.exs); these check what the project adds.
  describe "the Credentials tab" do
    test "an editor adds a credential to the project", %{
      conn: conn,
      user: user
    } do
      project = project_with(user, :editor)
      view = open(conn, project)

      send_event(
        view,
        "create_credential",
        raw_values(%{"projectIds" => [project.id]})
      )

      assert_ok(view)
      assert [credential] = Credentials.list_credentials(project)
      assert credential.user_id == user.id
      assert [%{"name" => "My raw"}] = props(view)["credentials"]["credentials"]
    end

    test "a credential added in a sandbox is shared with the sandbox", %{
      conn: conn,
      user: user
    } do
      parent = project_with(user, :owner, name: "root")
      sandbox = project_with(user, :admin, name: "sb", parent: parent)
      view = open(conn, sandbox)

      assert %{"id" => sandbox.id, "name" => "sb"} in props(view)["credentials"][
               "projects"
             ]

      send_event(
        view,
        "create_credential",
        raw_values(%{"projectIds" => [sandbox.id]})
      )

      assert_ok(view)
      assert [_credential] = Credentials.list_credentials(sandbox)
    end

    test "refuses a viewer a new credential or OAuth client", %{
      conn: conn,
      user: user
    } do
      project = project_with(user, :viewer)
      view = open(conn, project)
      refused = LightningWeb.CredentialPageHelpers.refused()

      send_event(
        view,
        "create_credential",
        raw_values(%{"projectIds" => [project.id]})
      )

      assert_reply(view, %{error: ^refused})

      send_event(
        view,
        "create_oauth_client",
        client_values(%{"projectIds" => [project.id]})
      )

      assert_reply(view, %{error: ^refused})

      assert Credentials.list_credentials(user) == []
      assert Repo.all(OauthClient) == []
    end

    test "an OAuth sign-in comes back to the page that started it", %{
      conn: conn,
      user: user
    } do
      project = project_with(user, :editor)
      client = insert(:oauth_client, user: user)
      insert(:project_oauth_client, project: project, oauth_client: client)
      stub_provider(client)
      view = open(conn, project)

      send_event(view, "authorize_oauth", %{
        "formId" => "form-1",
        "signInId" => "s1",
        "credentialId" => nil,
        "oauthClientId" => client.id,
        "scopes" => ["scope_1", "scope_2"],
        "environment" => "main"
      })

      assert_reply(view, %{authorizeUrl: url})

      %{"state" => state} =
        url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()

      get(
        build_conn(),
        ~p"/authenticate/callback?#{%{code: "the-code", state: state}}"
      )

      render_async(view)

      assert [%{"signInId" => "s1", "error" => nil}] =
               props(view)["credentials"]["oauthSignIns"]
    end
  end

  describe "keychains" do
    test "an admin creates, edits and deletes one", %{conn: conn, user: user} do
      project = project_with(user, :admin)
      view = open(conn, project)

      send_event(view, "create_keychain_credential", %{
        "name" => "by facility",
        "path" => "$.facility",
        "defaultCredentialId" => nil
      })

      assert_ok(view)

      assert [%{"id" => id, "name" => "by facility", "path" => "$.facility"}] =
               props(view)["credentials"]["keychainCredentials"]

      send_event(view, "update_keychain_credential", %{
        "id" => id,
        "name" => "by district",
        "path" => "$.district",
        "defaultCredentialId" => nil
      })

      assert_ok(view)
      assert [%{name: "by district"}] = keychains(project)

      send_event(view, "delete_keychain_credential", %{"id" => id})
      assert_ok(view)
      assert keychains(project) == []
      assert props(view)["credentials"]["keychainCredentials"] == []
    end

    test "refuses an editor", %{conn: conn, user: user} do
      project = project_with(user, :editor)
      keychain = insert(:keychain_credential, project: project, name: "kept")
      view = open(conn, project)

      for {event, payload} <- [
            {"create_keychain_credential",
             %{"name" => "new", "path" => "$.id", "defaultCredentialId" => nil}},
            {"update_keychain_credential",
             %{
               "id" => keychain.id,
               "name" => "renamed",
               "path" => "$.id",
               "defaultCredentialId" => nil
             }},
            {"delete_keychain_credential", %{"id" => keychain.id}}
          ] do
        send_event(view, event, payload)
        assert_refused(view)
      end

      assert [%{name: "kept"}] = keychains(project)
    end

    test "refuses one from another project, even one the user admins", %{
      conn: conn,
      user: user
    } do
      project = project_with(user, :admin)
      elsewhere = project_with(user, :admin)
      keychain = insert(:keychain_credential, project: elsewhere, name: "kept")
      view = open(conn, project)

      send_event(view, "update_keychain_credential", %{
        "id" => keychain.id,
        "name" => "renamed",
        "path" => "$.id",
        "defaultCredentialId" => nil
      })

      assert_refused(view)
      send_event(view, "delete_keychain_credential", %{"id" => keychain.id})
      assert_refused(view)
      assert [%{name: "kept"}] = keychains(elsewhere)
    end
  end

  describe "collections" do
    test "an admin creates, renames, previews and deletes one", %{
      conn: conn,
      user: user
    } do
      project = project_with(user, :admin)
      view = open(conn, project)

      send_event(view, "create_collection", %{"rawName" => "My Things"})
      assert_ok(view)

      assert [%{"id" => id, "name" => "my-things"}] =
               props(view)["collections"]["collections"]

      send_event(view, "rename_collection", %{"id" => id, "rawName" => "stuff"})
      assert_ok(view)
      assert [%{name: "stuff"} = collection] = collections(project)

      send_event(view, "preview_collection", %{"id" => id})
      assert_reply(view, %{record: nil})

      insert(:collection_item, collection: collection, key: "k1", value: "v1")
      send_event(view, "preview_collection", %{"id" => id})
      assert_reply(view, %{record: record})
      assert [%{"key" => "k1", "value" => "v1"}] = Jason.decode!(record)

      send_event(view, "delete_collection", %{"id" => id})
      assert_ok(view)
      assert collections(project) == []
    end

    test "refuses one from another project, even one the user admins", %{
      conn: conn,
      user: user
    } do
      project = project_with(user, :admin)
      elsewhere = project_with(user, :admin)
      collection = insert(:collection, project: elsewhere, name: "kept")
      view = open(conn, project)

      for {event, payload} <- [
            {"rename_collection",
             %{"id" => collection.id, "rawName" => "renamed"}},
            {"delete_collection", %{"id" => collection.id}},
            {"preview_collection", %{"id" => collection.id}}
          ] do
        send_event(view, event, payload)
        assert_reply(view, %{error: "Collection not found"})
      end

      assert [%{name: "kept"}] = collections(elsewhere)
    end

    test "refuses an editor", %{conn: conn, user: user} do
      project = project_with(user, :editor)
      collection = insert(:collection, project: project, name: "kept")
      view = open(conn, project)

      for {event, payload} <- [
            {"create_collection", %{"rawName" => "new"}},
            {"rename_collection",
             %{"id" => collection.id, "rawName" => "renamed"}},
            {"delete_collection", %{"id" => collection.id}}
          ] do
        send_event(view, event, payload)
        assert_refused(view)
      end

      assert [%{name: "kept"}] = collections(project)
    end
  end

  describe "webhook auth methods" do
    test "an admin creates a basic method, renames it and deletes it", %{
      conn: conn,
      user: user
    } do
      project = project_with(user, :admin)
      view = open(conn, project)

      send_event(view, "create_webhook_auth_method", %{
        "authType" => "basic",
        "name" => "first",
        "username" => "My User",
        "password" => "long enough"
      })

      assert_ok(view)
      assert [%{username: "my-user"} = method] = auth_methods(project)

      assert [%{"id" => id, "name" => "first", "maskedSecret" => masked}] =
               props(view)["webhookSecurity"]["authMethods"]

      assert masked == String.duplicate("*", 11)

      send_event(view, "rename_webhook_auth_method", %{
        "id" => id,
        "name" => "renamed"
      })

      assert_ok(view)
      assert [%{name: "renamed"}] = auth_methods(project)

      send_event(view, "delete_webhook_auth_method", %{"id" => id})
      assert_ok(view)
      assert Repo.reload(method).scheduled_deletion
    end

    test "an API key method gets the key handed out, which stays out of the props",
         %{conn: conn, user: user} do
      project = project_with(user, :admin)
      view = open(conn, project)

      send_event(view, "generate_api_key", %{})
      assert_reply(view, %{apiKey: api_key})

      send_event(view, "create_webhook_auth_method", %{
        "authType" => "api",
        "name" => "keyed"
      })

      assert_ok(view)
      assert [%{api_key: ^api_key}] = auth_methods(project)
      refute render(view) =~ api_key
    end

    test "answers a short password with its field error", %{
      conn: conn,
      user: user
    } do
      view = open(conn, project_with(user, :admin))

      send_event(view, "create_webhook_auth_method", %{
        "authType" => "basic",
        "name" => "first",
        "username" => "me",
        "password" => "short"
      })

      assert_reply(view, %{fieldErrors: %{"password" => [_message]}})
    end

    test "reveals a secret only once the password checks", %{
      conn: conn,
      user: user
    } do
      project = project_with(user, :admin)
      method = insert(:webhook_auth_method, project: project)
      view = open(conn, project)

      send_event(view, "reveal_webhook_secret", %{
        "id" => method.id,
        "password" => "wrong",
        "code" => ""
      })

      assert_reply(view, %{error: "Invalid! Please try again"})

      send_event(view, "reveal_webhook_secret", %{
        "id" => method.id,
        "password" => "hello world!",
        "code" => ""
      })

      assert_reply(view, %{secret: "password"})
    end

    test "refuses an editor", %{conn: conn, user: user} do
      project = project_with(user, :editor)
      method = insert(:webhook_auth_method, project: project, name: "kept")
      view = open(conn, project)

      for {event, payload} <- [
            {"generate_api_key", %{}},
            {"create_webhook_auth_method",
             %{"authType" => "api", "name" => "new"}},
            {"rename_webhook_auth_method",
             %{"id" => method.id, "name" => "renamed"}},
            {"delete_webhook_auth_method", %{"id" => method.id}},
            {"reveal_webhook_secret",
             %{"id" => method.id, "password" => "hello world!", "code" => ""}}
          ] do
        send_event(view, event, payload)
        assert_refused(view)
      end

      assert [%{name: "kept", scheduled_deletion: nil}] = auth_methods(project)
    end

    test "refuses one from another project, even one the user admins", %{
      conn: conn,
      user: user
    } do
      project = project_with(user, :admin)
      elsewhere = project_with(user, :admin)
      method = insert(:webhook_auth_method, project: elsewhere, name: "kept")
      view = open(conn, project)

      for {event, payload} <- [
            {"rename_webhook_auth_method",
             %{"id" => method.id, "name" => "renamed"}},
            {"delete_webhook_auth_method", %{"id" => method.id}},
            {"reveal_webhook_secret",
             %{"id" => method.id, "password" => "hello world!", "code" => ""}}
          ] do
        send_event(view, event, payload)
        assert_reply(view, %{error: "Webhook auth method not found"})
      end

      assert [%{name: "kept", scheduled_deletion: nil}] =
               auth_methods(elsewhere)
    end

    test "a sandbox's methods are managed from its parent", %{
      conn: conn,
      user: user
    } do
      parent = project_with(user, :admin)
      sandbox = project_with(user, :admin, parent: parent)
      method = insert(:webhook_auth_method, project: sandbox, name: "kept")
      view = open(conn, sandbox)

      for {event, payload} <- [
            {"generate_api_key", %{}},
            {"create_webhook_auth_method",
             %{"authType" => "api", "name" => "new"}},
            {"rename_webhook_auth_method",
             %{"id" => method.id, "name" => "renamed"}},
            {"delete_webhook_auth_method", %{"id" => method.id}},
            {"reveal_webhook_secret",
             %{"id" => method.id, "password" => "hello world!", "code" => ""}}
          ] do
        send_event(view, event, payload)
        assert_refused(view)
      end

      assert [%{name: "kept", scheduled_deletion: nil}] = auth_methods(sandbox)
    end

    test "only those who may edit a method see its username and secret", %{
      conn: conn,
      user: user
    } do
      project = project_with(user, :viewer)
      insert(:webhook_auth_method, project: project, username: "kept-user")

      assert [%{"username" => nil, "maskedSecret" => ""}] =
               props(open(conn, project))["webhookSecurity"]["authMethods"]
    end
  end

  describe "collaborators" do
    test "an admin adds those with accounts and is told who to invite", %{
      conn: conn,
      user: user
    } do
      project = owned_project_with(user, :admin)
      other = insert(:user)
      view = open(conn, project)

      send_event(view, "add_collaborators", %{
        "collaborators" => [
          %{"email" => other.email, "role" => "editor"},
          %{"email" => "new@example.org", "role" => "viewer"}
        ]
      })

      assert_reply(view, %{
        toInvite: [%{email: "new@example.org", role: :viewer}]
      })

      assert role_of(project, other) == :editor

      assert Enum.any?(
               props(view)["collaboration"]["collaborators"],
               &(&1["email"] == other.email)
             )
    end

    test "invites a new user with the role asked for", %{
      conn: conn,
      user: user
    } do
      project = owned_project_with(user, :admin)
      view = open(conn, project)

      send_event(view, "invite_collaborators", %{
        "collaborators" => [
          %{
            "email" => "ada@example.org",
            "firstName" => "Ada",
            "lastName" => "Lovelace",
            "role" => "editor"
          }
        ]
      })

      assert_ok(view)

      assert role_of(project, Repo.get_by(User, email: "ada@example.org")) ==
               :editor
    end

    test "refuses an editor adding, inviting or removing", %{
      conn: conn,
      user: user
    } do
      other = insert(:user)

      project =
        insert(:project,
          project_users: [
            %{user: user, role: :editor},
            %{user: other, role: :viewer}
          ]
        )

      view = open(conn, project)
      row = %{"email" => "new@example.org", "role" => "viewer"}

      for {event, payload} <- [
            {"add_collaborators", %{"collaborators" => [row]}},
            {"invite_collaborators",
             %{
               "collaborators" => [
                 Map.merge(row, %{"firstName" => "A", "lastName" => "B"})
               ]
             }},
            {"remove_collaborator", %{"id" => project_user_id(project, other)}}
          ] do
        send_event(view, event, payload)
        assert_refused(view)
      end

      assert role_of(project, other) == :viewer
      refute Repo.get_by(User, email: "new@example.org")
    end

    test "a removed collaborator's credentials leave the Credentials tab", %{
      conn: conn,
      user: user
    } do
      project = owned_project_with(user, :admin)
      other = insert(:user)
      insert(:project_user, project: project, user: other, role: :viewer)

      insert(:credential,
        name: "theirs",
        user: other,
        project_credentials: [%{project_id: project.id}]
      )

      view = open(conn, project)
      assert ["theirs"] = credential_names(view)

      send_event(view, "remove_collaborator", %{
        "id" => project_user_id(project, other)
      })

      assert_ok(view)
      assert credential_names(view) == []
    end

    test "support access is set to the value asked for", %{
      conn: conn,
      user: user
    } do
      project = project_with(user, :admin)
      view = open(conn, project)

      for _twice <- 1..2 do
        send_event(view, "set_support_access", %{"on" => true})
        assert_ok(view)
        assert Repo.reload(project).allow_support_access
      end

      send_event(view, "set_support_access", %{"on" => false})
      assert_ok(view)
      refute Repo.reload(project).allow_support_access
    end
  end

  # The instance limits these actions, with a banner naming each.
  defp limit(types) do
    Mox.stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn
      %{type: type}, _context ->
        if type in types do
          {:error, :disabled,
           %Lightning.Extensions.Message{
             text: "#{type} is not on your plan",
             attrs: %{text: "#{type} is not on your plan"},
             function: fn assigns -> ~H"{@text}" end
           }}
        else
          :ok
        end
    end)
  end

  describe "security" do
    test "MFA is set to the value asked for", %{conn: conn, user: user} do
      # Once the project requires MFA, only members with MFA may change it.
      user |> Ecto.Changeset.change(mfa_enabled: true) |> Repo.update!()
      project = project_with(user, :admin)
      view = open(conn, project)

      for _twice <- 1..2 do
        send_event(view, "set_requires_mfa", %{"on" => true})
        assert_ok(view)
        assert Repo.reload(project).requires_mfa
      end

      send_event(view, "set_requires_mfa", %{"on" => false})
      assert_ok(view)
      refute Repo.reload(project).requires_mfa
    end
  end

  describe "data storage" do
    test "an instance's retention limit component is drawn under the tab", %{
      conn: conn,
      user: user
    } do
      Mox.stub(
        Lightning.Extensions.MockUsageLimiter,
        :get_data_retention_message,
        fn _context ->
          %Lightning.Extensions.Message{
            attrs: %{text: "Upgrade to keep more"},
            function: fn assigns -> ~H"{@text}" end
          }
        end
      )

      view = open(conn, project_with(user, :admin))

      assert view
             |> element(
               "#project-settings-data-retention-limit[data-hash=data-storage]"
             )
             |> render() =~ "Upgrade to keep more"

      assert props(view)["dataStorage"]["limitMessage"] == nil
    end

    test "saves the retention fields only", %{conn: conn, user: user} do
      project = project_with(user, :admin)
      view = open(conn, project)

      send_event(view, "save_data_storage", %{
        "historyRetentionPeriod" => 90,
        "dataclipRetentionPeriod" => 30,
        "retentionPolicy" => "retain_with_errors",
        "requiresMfa" => true,
        "name" => "renamed"
      })

      assert_ok(view)

      assert %{
               history_retention_period: 90,
               dataclip_retention_period: 30,
               retention_policy: :retain_with_errors,
               requires_mfa: false
             } = saved = Repo.reload(project)

      assert saved.name == project.name
    end

    test "erasing all keeps no input/output period", %{conn: conn, user: user} do
      project =
        project_with(user, :admin,
          history_retention_period: 90,
          dataclip_retention_period: 30
        )

      view = open(conn, project)

      send_event(view, "save_data_storage", %{
        "historyRetentionPeriod" => 90,
        "dataclipRetentionPeriod" => 30,
        "retentionPolicy" => "erase_all"
      })

      assert_ok(view)

      assert %{retention_policy: :erase_all, dataclip_retention_period: nil} =
               Repo.reload(project)
    end

    test "replies the field error for a period longer than the history's", %{
      conn: conn,
      user: user
    } do
      project = project_with(user, :admin)
      view = open(conn, project)

      send_event(view, "save_data_storage", %{
        "historyRetentionPeriod" => 7,
        "dataclipRetentionPeriod" => 30,
        "retentionPolicy" => "retain_all"
      })

      assert_reply(view, %{fieldErrors: %{"dataclipRetentionPeriod" => [_]}})
      assert Repo.reload(project).history_retention_period == nil
    end
  end

  describe "sync to GitHub" do
    import Lightning.GithubHelpers

    defp connected_project_with(user, role) do
      project = project_with(user, role)
      insert(:project_repo_connection, project: project)
      project
    end

    defp stub_github do
      Mox.stub(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %Tesla.Env{status: 404, body: %{"message" => "not found"}}}
      end)
    end

    @tag :capture_log
    test "a sync goes to the project's connection and replies its error", %{
      conn: conn,
      user: user
    } do
      project = connected_project_with(user, :editor)

      # Both hyphenate to `My-Flow`, so the export refuses before GitHub.
      for name <- ["My Flow", "My-Flow"] do
        {:ok, _} =
          insert(:simple_workflow, name: name, project: project)
          |> Lightning.Workflows.Snapshot.create()
      end

      view = open(conn, project)
      send_event(view, "sync_github", %{})
      assert_reply(view, %{error: error})
      assert error =~ "two workflows in this project"
    end

    test "a sync replies the instance's limit", %{conn: conn, user: user} do
      limit([:github_sync])
      view = open(conn, connected_project_with(user, :admin))

      refute props(view)["githubSync"]["canInitiateSync"]
      send_event(view, "sync_github", %{})
      assert_reply(view, %{error: "github_sync is not on your plan"})
    end

    test "a limit drawn only as a component still replies a message", %{
      conn: conn,
      user: user
    } do
      Mox.stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn
        %{type: type}, _context when type in [:github_sync, :new_user] ->
          {:error, :disabled,
           %Lightning.Extensions.Message{
             attrs: %{},
             function: fn assigns -> ~H"Upgrade" end
           }}

        _action, _context ->
          :ok
      end)

      view = open(conn, connected_project_with(user, :admin))

      send_event(view, "sync_github", %{})
      assert_reply(view, %{error: "This action is limited for this project."})

      send_event(view, "add_collaborators", %{
        "collaborators" => [%{"email" => "new@example.org", "role" => "viewer"}]
      })

      assert_reply(view, %{error: "This action is limited for this project."})
    end

    @tag :capture_log
    test "an admin removes the connection", %{conn: conn, user: user} do
      stub_github()
      project = connected_project_with(user, :admin)
      view = open(conn, project)

      send_event(view, "remove_github_connection", %{})
      assert_ok(view)

      refute Lightning.VersionControl.get_repo_connection_for_project(project.id)

      assert props(view)["githubSync"]["connection"] == nil
    end

    test "with no connection, replies that there is none", %{
      conn: conn,
      user: user
    } do
      view = open(conn, project_with(user, :admin))
      send_event(view, "sync_github", %{})
      assert_reply(view, %{error: "GitHub connection not found"})
    end

    test "draws the old form to connect a repository beside the page", %{
      conn: conn,
      user: user
    } do
      Mox.stub(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:ok, %Tesla.Env{status: 200, body: %{"installations" => []}}}
      end)

      set_valid_github_oauth_token!(user)
      project = project_with(user, :admin)
      view = open(conn, project)
      render_async(view)

      assert has_element?(
               view,
               "#project-settings-vcs-hosted[data-hash=vcs] #project-repo-connection-form"
             )

      insert(:project_repo_connection, project: project)

      refute conn
             |> open(project)
             |> has_element?("#project-settings-vcs-hosted")
    end
  end

  # Membership changes need the project to keep its one owner.
  defp owned_project_with(user, role),
    do:
      insert(:project,
        project_users: [
          %{user: user, role: role},
          %{user: insert(:user), role: :owner}
        ]
      )

  defp auth_methods(project),
    do: Lightning.WebhookAuthMethods.list_for_project(project)

  defp credential_names(view),
    do: Enum.map(props(view)["credentials"]["credentials"], & &1["name"])

  defp project_user_id(project, user),
    do: Repo.get_by!(ProjectUser, project_id: project.id, user_id: user.id).id

  defp role_of(project, user) do
    case Repo.get_by(ProjectUser, project_id: project.id, user_id: user.id) do
      nil -> nil
      project_user -> project_user.role
    end
  end

  defp keychains(project),
    do: Credentials.list_keychain_credentials_for_project(project)

  defp collections(project), do: Collections.list_project_collections(project)

  describe "parts an instance configures" do
    defp route_with(metadata) do
      stub(Phoenix.Router, :route_info, fn router, method, path, host ->
        Phoenix.Router
        |> call_original(:route_info, [router, method, path, host])
        |> Map.merge(metadata)
      end)
    end

    test "Lightning's own concurrency input is the page's switch", %{
      conn: conn,
      user: user
    } do
      project = project_with(user, :admin)
      view = open(conn, project)

      refute has_element?(view, "#project-settings-hosted")
      assert %{"concurrency" => nil} = props(view)["setup"]
    end

    test "another concurrency input is drawn beside the page", %{
      conn: conn,
      user: user
    } do
      route_with(%{concurrency_input: LightningWeb.SlotEchoComponent})
      project = project_with(user, :viewer)
      view = open(conn, project)

      assert has_element?(
               view,
               "#project-settings-hosted[data-hash=project] #concurrency-input-component" <>
                 "[data-project-id='#{project.id}'][data-disabled=true]"
             )
    end

    test "a usage caps input is drawn beside the page", %{
      conn: conn,
      user: user
    } do
      route_with(%{usage_caps_input: LightningWeb.SlotEchoComponent})
      project = project_with(user, :admin)
      view = open(conn, project)

      assert has_element?(
               view,
               "#project-settings-hosted #usage-caps-input-component" <>
                 "[data-current-user-id='#{user.id}']"
             )
    end

    test "the MFA and GitHub limit banners are drawn under their tabs", %{
      conn: conn,
      user: user
    } do
      limit([:require_mfa, :github_sync])
      view = open(conn, project_with(user, :admin))

      assert view
             |> element("#project-settings-mfa-banner[data-hash=security]")
             |> render() =~ "require_mfa is not on your plan"

      assert view
             |> element("#project-settings-vcs-hosted[data-hash=vcs]")
             |> render() =~ "github_sync is not on your plan"
    end
  end
end
