defmodule LightningWeb.CredentialLiveTest do
  use LightningWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import LightningWeb.CredentialLiveHelpers
  import LightningWeb.CredentialPageHelpers

  import Lightning.AdaptorTestHelpers
  import Lightning.Factories

  import Ecto.Query
  import Swoosh.TestAssertions

  alias Lightning.Accounts.User
  alias Lightning.Credentials
  alias Lightning.Credentials.Credential

  @create_attrs %{
    name: "some credential",
    external_id: "test-external-id"
  }

  @update_attrs %{
    name: "some updated name",
    body: "{\"a\":\"new_secret\"}",
    external_id: "updated-external-id"
  }

  # An apostrophe is a legal name character. A control character is not.
  @invalid_attrs %{name: "this won't \u{0000} work"}

  defp create_credential(%{user: user}) do
    credential = insert(:credential, user: user)
    %{credential: credential}
  end

  defp create_project_credential(%{user: user}) do
    project_credential =
      insert(:project_credential, credential: build(:credential, user: user))

    %{project_credential: project_credential}
  end

  setup :register_and_log_in_user
  setup :create_project_for_current_user
  setup :isolated_adaptors

  setup do
    Lightning.AdaptorTestHelpers.seed_all_credential_schemas()
    :ok
  end

  describe "Index" do
    setup [:create_credential, :create_project_credential]

    test "Side menu has credentials and user profile navigation", %{
      conn: conn
    } do
      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      # The side menu is drawn by React from the layout's bridge; the profile
      # menu's links are tested in assets/test/design-system/shell.test.tsx.
      props = page_props(index_live, "#sidebar-bridge")
      assert %{"variant" => "profile"} = props
      refute Map.has_key?(props, "project")
    end

    test "lists all credentials", %{
      conn: conn,
      credential: credential
    } do
      view = open(conn)

      # The table, its headings and its actions are the design system's;
      # the page draws them from these rows.
      rows = props(view)["credentials"]

      [[], project_names] =
        Credentials.list_credentials(%User{id: credential.user_id})
        |> Enum.sort_by(&(&1.project_credentials |> length))
        |> Enum.map(fn c ->
          Enum.map(c.projects, fn p -> p.name end)
        end)

      assert project_names in Enum.map(rows, fn row ->
               Enum.map(row["projects"], & &1["name"])
             end)

      assert %{"schema" => schema, "canEdit" => true} =
               Enum.find(rows, &(&1["id"] == credential.id))

      assert schema == credential.schema
      assert length(rows) == 2
    end

    test "ensure support user only sees credentials they own on /credentials", %{
      conn: conn,
      user: user,
      credential: credential
    } do
      _user = Repo.update!(Changeset.change(user, %{support_user: true}))

      %{credential: support_credential} =
        insert(:project_credential,
          project: build(:project, allow_support_access: true)
        )

      view = open(conn)

      names = Enum.map(props(view)["credentials"], & &1["name"])

      assert credential.name in names
      assert length(names) == 2
      refute support_credential.name in names
      refute render(view) =~ support_credential.name
    end

    test "can schedule for deletion a credential that is not associated to any activity",
         %{
           conn: conn,
           credential: credential
         } do
      view = open(conn)

      # The delete dialog is the design system's; it warns about runs from
      # this flag.
      assert %{"hasActivityInProjects" => false, "scheduledDeletion" => nil} =
               Enum.find(
                 props(view)["credentials"],
                 &(&1["id"] == credential.id)
               )

      assert send_event(view, "delete_credential", %{
               "id" => credential.id,
               "now" => false
             }) =~ "Credential scheduled for deletion"

      assert Repo.reload!(credential).scheduled_deletion

      assert %{"scheduledDeletion" => scheduled} =
               Enum.find(
                 props(view)["credentials"],
                 &(&1["id"] == credential.id)
               )

      assert scheduled
    end

    test "rejects deleting another user's credential via a tampered id", %{
      conn: conn,
      credential: credential
    } do
      # a credential owned by a different user
      other = insert(:credential, user: insert(:user), name: "someone-elses")

      view = open(conn)

      send_event(view, "delete_credential", %{"id" => other.id, "now" => false})

      # the request is rejected, and nothing is scheduled for deletion: not the
      # foreign credential, and not the viewer's own
      assert_reply(view, %{error: error})
      assert error == refused()
      assert Lightning.Repo.reload!(other).scheduled_deletion == nil
      assert Lightning.Repo.reload!(credential).scheduled_deletion == nil
    end

    test "can schedule for deletion a credential that is associated to activities",
         %{
           conn: conn,
           credential: credential
         } do
      insert(:step, credential: credential)

      view = open(conn)

      # The dialog's "used in workflow runs" warning comes from this flag.
      assert %{"hasActivityInProjects" => true} =
               Enum.find(
                 props(view)["credentials"],
                 &(&1["id"] == credential.id)
               )

      assert send_event(view, "delete_credential", %{
               "id" => credential.id,
               "now" => false
             }) =~ "Credential scheduled for deletion"

      assert Repo.reload!(credential).scheduled_deletion
    end

    test "cancel a scheduled for deletion credential", %{
      conn: conn,
      user: user,
      credential: credential
    } do
      insert(:step, credential: credential)

      {:ok, credential} =
        Credentials.schedule_credential_deletion(credential, user)

      assert credential.scheduled_deletion

      view = open(conn)

      assert send_event(view, "cancel_credential_deletion", %{
               "id" => credential.id
             }) =~ "Credential deletion canceled"

      refute Lightning.Repo.reload(credential).scheduled_deletion
    end

    test "can delete credential that has no activity in projects", %{
      conn: conn,
      user: user,
      credential: credential
    } do
      {:ok, credential} =
        Credentials.schedule_credential_deletion(credential, user)

      view = open(conn)

      assert %{"hasActivityInProjects" => false} =
               Enum.find(
                 props(view)["credentials"],
                 &(&1["id"] == credential.id)
               )

      assert send_event(view, "delete_credential", %{
               "id" => credential.id,
               "now" => true
             }) =~ "Credential deleted successfully"

      refute Repo.get(Credential, credential.id)
    end

    test "cannot delete credential that has activity in projects", %{
      conn: conn,
      user: user,
      credential: credential
    } do
      insert(:step, credential: credential)

      {:ok, credential} =
        Credentials.schedule_credential_deletion(credential, user)

      view = open(conn)

      # The dialog only offers "Ok, understood" for a credential with this
      # flag; sending the event anyway is refused.
      assert %{"hasActivityInProjects" => true} =
               Enum.find(
                 props(view)["credentials"],
                 &(&1["id"] == credential.id)
               )

      send_event(view, "delete_credential", %{
        "id" => credential.id,
        "now" => true
      })

      assert_reply(view, %{
        error: "Cannot delete a credential that has activities in projects"
      })

      assert Repo.get(Credential, credential.id)
    end

    test "non credential owner cannot delete credentials in project settings page",
         %{
           conn: conn,
           user: user
         } do
      credential_owner = insert(:user)

      project =
        insert(:project,
          project_users: [
            %{user: user, role: :owner},
            %{user: credential_owner, role: :admin}
          ]
        )

      credential =
        insert(:credential,
          user: credential_owner,
          project_credentials: [%{project: project}]
        )

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project}/settings#credentials",
          on_error: :raise
        )

      assert html =~ credential.name

      refute has_element?(
               view,
               "#credential-actions-#{credential.id}-delete"
             )

      # send the event anyway
      view
      |> with_target("#credentials-index-component")
      |> render_click("request_credential_deletion", %{id: credential.id})

      assert_patched(view, ~p"/projects/#{project}/settings")

      assert render(view) =~ "You are not authorized to perform this action"

      credential =
        Lightning.Repo.get(Lightning.Credentials.Credential, credential.id)

      refute credential.scheduled_deletion
    end

    test "cannot cancel the scheduled deletion of another user's credential", %{
      conn: conn
    } do
      other_credential =
        insert(:credential,
          user: insert(:user),
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      view = open(conn)

      refute Enum.any?(
               props(view)["credentials"],
               &(&1["id"] == other_credential.id)
             )

      # send the event anyway
      send_event(view, "cancel_credential_deletion", %{
        "id" => other_credential.id
      })

      assert_reply(view, %{error: error})
      assert error == refused()
      assert Lightning.Repo.reload(other_credential).scheduled_deletion
    end

    test "non credential owner cannot cancel a scheduled deletion in project settings page",
         %{
           conn: conn,
           user: user
         } do
      credential_owner = insert(:user)

      project =
        insert(:project,
          project_users: [
            %{user: user, role: :owner},
            %{user: credential_owner, role: :admin}
          ]
        )

      # Set scheduled_deletion directly rather than via
      # schedule_credential_deletion/1, which detaches the project associations
      # the credential needs to stay visible on this page.
      credential =
        insert(:credential,
          user: credential_owner,
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second),
          project_credentials: [%{project: project}]
        )

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project}/settings#credentials",
          on_error: :raise
        )

      assert html =~ credential.name

      refute has_element?(
               view,
               "#credential-actions-#{credential.id}-cancel-deletion"
             )

      # send the event anyway
      view
      |> with_target("#credentials-index-component")
      |> render_click("cancel_credential_deletion", %{id: credential.id})

      assert_patched(view, ~p"/projects/#{project}/settings")

      assert render(view) =~ "You are not authorized to perform this action"

      assert Lightning.Repo.reload(credential).scheduled_deletion
    end

    test "delete credentials in project settings page", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project,
          project_users: [
            %{user: user, role: :owner}
          ]
        )

      credential =
        insert(:credential,
          user: user,
          project_credentials: [%{project: project}]
        )

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project}/settings#credentials",
          on_error: :raise
        )

      assert html =~ credential.name

      html = open_delete_credential_modal(view, credential.id)

      assert html =~
               "Deleting this credential will immediately remove it from all jobs"

      view
      |> element(
        "#delete-credential-#{credential.id}-modal button",
        "Delete credential"
      )
      |> render_click()

      flash =
        assert_redirected(view, ~p"/projects/#{project}/settings#credentials")

      assert flash["info"] == "Credential scheduled for deletion"

      credential =
        Lightning.Repo.get(Lightning.Credentials.Credential, credential.id)

      assert credential.scheduled_deletion
    end

    test "doesn't show delete credential to support user", %{
      conn: conn,
      user: user
    } do
      _user = Repo.update!(Changeset.change(user, %{support_user: true}))

      project =
        insert(:project,
          allow_support_access: true,
          project_users: [%{user: build(:user), role: :owner}]
        )

      credential =
        insert(:credential,
          user: build(:user),
          project_credentials: [%{project: project}]
        )

      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project}/settings#credentials",
          on_error: :raise
        )

      assert view
             |> element("#credentials-table")
             |> render()
             |> Floki.parse_fragment!()
             |> Floki.find("tr td:first-child")
             |> Floki.text() =~ credential.name

      refute has_element?(
               view,
               "#credential-actions-#{credential.id}-delete"
             )

      # send the event anyway
      view
      |> with_target("#credentials-index-component")
      |> render_click("request_credential_deletion", %{id: credential.id})

      assert_patched(view, ~p"/projects/#{project}/settings")

      assert render(view) =~ "You are not authorized to perform this action"
    end
  end

  describe "Clicking new from the list view" do
    test "allows the user to define and save a new raw credential", %{
      conn: conn,
      user: user,
      project: project1
    } do
      project2 = insert(:project, project_users: [%{user: user, role: :admin}])

      view = open(conn)

      # The type picker and the project chips are the design system's; the
      # page offers Raw JSON and the projects the viewer may share with.
      assert MapSet.new(props(view)["projects"], & &1["id"]) ==
               MapSet.new([project1.id, project2.id])

      send_event(view, "create_credential", raw_values(%{"name" => ""}))
      assert_reply(view, %{fieldErrors: %{"name" => [_]}})

      # An apostrophe is a legal name character.
      assert send_event(
               view,
               "create_credential",
               raw_values(%{"formId" => "form-2", "name" => "MailChimp'24"})
             ) =~ "Credential created successfully"

      send_event(
        view,
        "create_credential",
        raw_values(%{"name" => "bad\u{0000}name"})
      )

      assert_reply(view, %{fieldErrors: %{"name" => [message]}})
      assert message =~ "credential name can't contain control characters"

      html =
        send_event(
          view,
          "create_credential",
          raw_values(%{
            "name" => @create_attrs.name,
            "externalId" => @create_attrs.external_id,
            "projectIds" => [project1.id, project2.id]
          })
        )

      assert html =~ "Credential created successfully"

      assert %{"projects" => projects, "externalId" => "test-external-id"} =
               Enum.find(
                 props(view)["credentials"],
                 &(&1["name"] == @create_attrs.name)
               )

      assert project1.name in Enum.map(projects, & &1["name"])

      credential =
        Repo.get_by(Credential, name: @create_attrs.name)
        |> Repo.preload(:projects)

      assert MapSet.equal?(
               MapSet.new(credential.projects, & &1.id),
               MapSet.new([project1.id, project2.id])
             )
    end

    test "validates raw credential body and shows errors after interaction", %{
      conn: conn,
      user: user
    } do
      view = open(conn)

      # The form checks the body as it's typed (the design system's); the
      # server checks it again on save.
      for body <- ["", "not valid json"] do
        env = %{
          "name" => "main",
          "previousName" => nil,
          "body" => body,
          "signInId" => nil
        }

        send_event(
          view,
          "create_credential",
          raw_values(%{"name" => "Test Cred", "environments" => [env]})
        )

        assert_reply(view, %{
          fieldErrors: %{"environments.main" => ["Invalid JSON format"]}
        })
      end

      assert Credentials.list_credentials(user) == []

      assert send_event(
               view,
               "create_credential",
               raw_values(%{"name" => "Test Cred"})
             ) =~ "Credential created successfully"
    end

    test "allows a support user to define and save a new raw credential", %{
      conn: conn,
      user: user,
      project: project1
    } do
      _user = Repo.update!(Changeset.change(user, %{support_user: true}))

      project1 =
        Repo.update!(Changeset.change(project1, %{allow_support_access: true}))

      project2 =
        insert(:project,
          allow_support_access: true,
          project_users: [%{user: build(:user), role: :admin}]
        )

      view = open(conn)

      assert MapSet.new(props(view)["projects"], & &1["id"]) ==
               MapSet.new([project1.id, project2.id])

      send_event(view, "create_credential", raw_values(%{"name" => ""}))
      assert_reply(view, %{fieldErrors: %{"name" => [_]}})

      # An apostrophe is a legal name character.
      assert send_event(
               view,
               "create_credential",
               raw_values(%{"formId" => "form-2", "name" => "MailChimp'24"})
             ) =~ "Credential created successfully"

      send_event(
        view,
        "create_credential",
        raw_values(%{"name" => "bad\u{0000}name"})
      )

      assert_reply(view, %{fieldErrors: %{"name" => [message]}})
      assert message =~ "credential name can't contain control characters"

      html =
        send_event(
          view,
          "create_credential",
          raw_values(%{
            "name" => @create_attrs.name,
            "projectIds" => [project1.id, project2.id]
          })
        )

      assert html =~ "Credential created successfully"

      credential =
        Repo.get_by(Credential, name: @create_attrs.name)
        |> Repo.preload(:projects)

      assert MapSet.equal?(
               MapSet.new(credential.projects, & &1.id),
               MapSet.new([project1.id, project2.id])
             )
    end

    test "allows the user to define and save a new dhis2 credential", %{
      conn: conn,
      user: user
    } do
      view = open(conn)

      assert Enum.any?(props(view)["credentialTypes"], &(&1["key"] == "dhis2"))

      # The form draws these fields in this order.
      send_event(view, "load_credential_schema", %{"key" => "dhis2"})
      assert_reply(view, %{fields: fields})

      assert Enum.map(fields, & &1.key) ==
               ~w(username password hostUrl apiVersion)

      assert %{required: true} = Enum.find(fields, &(&1.key == "username"))

      dhis2 = fn body ->
        raw_values(%{
          "name" => "My Credential",
          "schema" => "dhis2",
          "environments" => [
            %{
              "name" => "main",
              "previousName" => nil,
              "body" => Jason.encode!(body),
              "signInId" => nil
            }
          ]
        })
      end

      send_event(
        view,
        "create_credential",
        dhis2.(%{"password" => "bar", "hostUrl" => "http://localhost"})
      )

      # The form names a blank required field before sending; the server
      # refuses the body anyway.
      assert_reply(view, %{fieldErrors: %{"environments.main" => [_ | _]}})

      send_event(
        view,
        "create_credential",
        dhis2.(%{"username" => "foo", "password" => "bar", "hostUrl" => "baz"})
      )

      assert_reply(view, %{fieldErrors: %{"environments.main" => [uri | _]}})
      assert uri =~ "expected to be a URI"
      assert Credentials.list_credentials(user) == []

      assert send_event(
               view,
               "create_credential",
               dhis2.(%{
                 "username" => "foo",
                 "password" => "bar",
                 "hostUrl" => "http://localhost"
               })
             ) =~ "Credential created successfully"

      assert [%{schema: "@openfn/language-dhis2"}] =
               Credentials.list_credentials(user)
    end

    test "allows the user to define and save a new postgresql credential", %{
      conn: conn,
      user: user
    } do
      view = open(conn)

      send_event(view, "load_credential_schema", %{"key" => "postgresql"})
      assert_reply(view, %{fields: fields})

      assert Enum.map(fields, & &1.key) ==
               ~w(host port database user password ssl allowSelfSignedCert)

      assert %{
               "port" => %{kind: "integer"},
               "ssl" => %{kind: "boolean"},
               "allowSelfSignedCert" => %{kind: "boolean"}
             } = Map.new(fields, &{&1.key, &1})

      credential_name = "Cast Postgres Credential"

      # The server casts the body to the adaptor's types.
      postgresql = fn body ->
        raw_values(%{
          "name" => credential_name,
          "schema" => "postgresql",
          "environments" => [
            %{
              "name" => "main",
              "previousName" => nil,
              "body" => Jason.encode!(body),
              "signInId" => nil
            }
          ]
        })
      end

      body = %{
        "user" => "user1",
        "password" => "pass1",
        "host" => "not a URI",
        "database" => "test_db",
        "port" => "5000",
        "ssl" => "true",
        "allowSelfSignedCert" => "false"
      }

      send_event(
        view,
        "create_credential",
        postgresql.(Map.delete(body, "user"))
      )

      # The form names a blank required field before sending; the server
      # refuses the body anyway.
      assert_reply(view, %{fieldErrors: %{"environments.main" => [_ | _]}})

      send_event(view, "create_credential", postgresql.(body))

      assert_reply(view, %{fieldErrors: %{"environments.main" => [uri | _]}})
      assert uri =~ "expected to be a URI"
      assert Credentials.list_credentials(user) == []

      assert send_event(
               view,
               "create_credential",
               postgresql.(%{body | "host" => "http://localhost"})
             ) =~ "Credential created successfully"

      credential =
        Lightning.Repo.get_by(Lightning.Credentials.Credential,
          name: credential_name
        )
        |> Lightning.Repo.preload(:credential_bodies)

      main_body = Enum.find(credential.credential_bodies, &(&1.name == "main"))

      assert %{
               "port" => 5000,
               "ssl" => true,
               "allowSelfSignedCert" => false
             } = main_body.body
    end

    test "allows the user to define and save a new http credential", %{
      conn: conn,
      user: user
    } do
      view = open(conn)

      send_event(view, "load_credential_schema", %{"key" => "http"})
      assert_reply(view, %{fields: fields})

      fields = Map.new(fields, &{&1.key, &1})
      assert %{required: false} = fields["baseUrl"]
      assert %{kind: "object"} = fields["tls"]

      http = fn body ->
        raw_values(%{
          "name" => "My Credential with TLS",
          "schema" => "http",
          "environments" => [
            %{
              "name" => "main",
              "previousName" => nil,
              "body" => Jason.encode!(body),
              "signInId" => nil
            }
          ]
        })
      end

      send_event(
        view,
        "create_credential",
        http.(%{"username" => "foo", "password" => "bar", "baseUrl" => "baz"})
      )

      assert_reply(view, %{fieldErrors: %{"environments.main" => [uri | _]}})
      assert uri =~ "expected to be a URI"
      assert Credentials.list_credentials(user) == []

      # An empty baseUrl is allowed: it isn't required.
      assert send_event(
               view,
               "create_credential",
               http.(%{
                 "access_token" => "",
                 "username" => "foo",
                 "password" => "bar",
                 "baseUrl" => "",
                 "tls" => %{"a" => 1}
               })
             ) =~ "Credential created successfully"

      credential =
        Repo.get_by(Lightning.Credentials.Credential,
          name: "My Credential with TLS"
        )
        |> Repo.preload(:credential_bodies)

      main_body = Enum.find(credential.credential_bodies, &(&1.name == "main"))

      assert main_body.body == %{
               "access_token" => "",
               "baseUrl" => "",
               "password" => "bar",
               "tls" => %{"a" => 1},
               "username" => "foo"
             }
    end

    test "allows the user to define and save a credential with email (godata)",
         %{
           conn: conn,
           user: user
         } do
      view = open(conn)

      godata = fn body ->
        raw_values(%{
          "name" => "Godata Credential",
          "schema" => "godata",
          "environments" => [
            %{
              "name" => "main",
              "previousName" => nil,
              "body" => Jason.encode!(body),
              "signInId" => nil
            }
          ]
        })
      end

      send_event(
        view,
        "create_credential",
        godata.(%{"apiUrl" => "http://url", "password" => "baz1234"})
      )

      # The form names a blank required field before sending; the server
      # refuses the body anyway.
      assert_reply(view, %{fieldErrors: %{"environments.main" => [_ | _]}})

      send_event(
        view,
        "create_credential",
        godata.(%{
          "apiUrl" => "http://url",
          "password" => "baz1234",
          "email" => "incomplete-email"
        })
      )

      assert_reply(view, %{fieldErrors: %{"environments.main" => [email | _]}})
      assert email =~ "expected to be an email"
      assert Credentials.list_credentials(user) == []

      assert send_event(
               view,
               "create_credential",
               godata.(%{
                 "apiUrl" => "http://url",
                 "password" => "baz1234",
                 "email" => "good@email.com"
               })
             ) =~ "Credential created successfully"
    end

    test "marks the fields whose type is unrecognized", %{
      conn: conn
    } do
      Mox.stub(Lightning.MockConfig, :sentry, fn -> Lightning.MockSentry end)
      Mox.stub(Lightning.MockSentry, :capture_message, fn _msg, _opts -> :ok end)

      view = open(conn)

      # The form draws the warning under a field that has one.
      send_event(view, "load_credential_schema", %{"key" => "unknownish"})
      assert_reply(view, %{fields: fields})

      fields = Map.new(fields, &{&1.key, &1})
      assert fields["port"].unrecognizedType =~ "badThing"
      refute fields["host"].unrecognizedType
    end

    test "marks no field of a known type as unrecognized", %{
      conn: conn
    } do
      view = open(conn)

      send_event(view, "load_credential_schema", %{"key" => "dhis2"})
      assert_reply(view, %{fields: fields})

      assert Enum.all?(fields, &is_nil(&1.unrecognizedType))
    end
  end

  describe "Edit" do
    setup [:create_credential]

    test "updates a credential", %{conn: conn, credential: credential} do
      view = open(conn)

      send_event(
        view,
        "update_credential",
        raw_values(%{"id" => credential.id, "name" => @invalid_attrs.name})
      )

      assert_reply(view, %{
        fieldErrors: %{
          "name" => ["credential name can't contain control characters"]
        }
      })

      assert send_event(
               view,
               "update_credential",
               raw_values(%{
                 "id" => credential.id,
                 "name" => @update_attrs.name,
                 "externalId" => @update_attrs.external_id,
                 "environments" => [
                   %{
                     "name" => "main",
                     "previousName" => nil,
                     "body" => @update_attrs.body,
                     "signInId" => nil
                   }
                 ]
               })
             ) =~ "Credential updated successfully"

      assert %{name: "some updated name", external_id: "updated-external-id"} =
               Repo.reload!(credential)

      assert bodies(credential) == %{"main" => %{"a" => "new_secret"}}

      assert [%{"name" => "some updated name"}] =
               Enum.filter(
                 props(view)["credentials"],
                 &(&1["id"] == credential.id)
               )
    end

    test "displays external_id in credentials table", %{
      conn: conn,
      user: user,
      credential: credential
    } do
      {:ok, _} =
        Credentials.update_credential(
          credential,
          %{external_id: "display-test-id"},
          user
        )

      assert %{"externalId" => "display-test-id"} =
               Enum.find(
                 props(open(conn))["credentials"],
                 &(&1["id"] == credential.id)
               )
    end

    test "Edit adds new project with access", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project, project_users: [build(:project_user, user: user)])

      credential =
        credential_with_body(
          user,
          %{name: "my-credential", schema: "http"},
          %{"username" => "test", "password" => "test"}
        )

      audit_events_query =
        from(a in Lightning.Credentials.Audit.base_query(),
          where: a.item_id == ^credential.id,
          select: {a.event, type(a.changes, :map)}
        )

      assert Lightning.Repo.all(audit_events_query) == []

      view = open(conn)

      send_event(
        view,
        "update_credential",
        raw_values(%{
          "id" => credential.id,
          "name" => "my-credential",
          "schema" => "http",
          "projectIds" => [project.id],
          "environments" => [
            %{
              "name" => "main",
              "previousName" => "main",
              "body" => ~s({"username": "test", "password": "test"}),
              "signInId" => nil
            }
          ]
        })
      )

      assert_reply(view, %{})

      assert [%{id: project_id}] =
               Repo.preload(credential, :projects, force: true).projects

      assert project_id == project.id

      audit_events = Lightning.Repo.all(audit_events_query)

      assert Enum.count(audit_events) == 2

      assert {"updated", _changes} =
               Enum.find(audit_events, fn {event, _changes} ->
                 event == "updated"
               end)

      assert {"added_to_project", _changes} =
               Enum.find(audit_events, fn {event, _changes} ->
                 event == "added_to_project"
               end)
    end

    test "cannot add new project with access by support user", %{
      conn: conn,
      user: user
    } do
      _user = Repo.update!(Changeset.change(user, %{support_user: true}))

      project =
        insert(:project,
          allow_support_access: true,
          project_users: [build(:project_user, user: build(:user))]
        )

      project_user = insert(:project_user, project: project, user: build(:user))

      %{credential: credential} =
        insert(:project_credential,
          credential:
            build(:credential,
              name: "my-credential",
              schema: "http",
              body: %{"username" => "test", "password" => "test"},
              user: project_user.user
            ),
          project: project
        )

      view = open(conn)

      refute Enum.any?(props(view)["credentials"], &(&1["id"] == credential.id))

      send_event(
        view,
        "update_credential",
        raw_values(%{
          "id" => credential.id,
          "schema" => "http",
          "projectIds" => [project.id, insert(:project).id]
        })
      )

      assert_reply(view, %{error: _})

      assert [_only_one] =
               Repo.preload(credential, :projects, force: true).projects
    end

    test "removes project with access", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project, project_users: [build(:project_user, user: user)])

      credential =
        credential_with_body(
          user,
          %{name: "my-credential", schema: "http"},
          %{"username" => "test", "password" => "test"}
        )

      insert(:project_credential, project: project, credential: credential)

      audit_events_query =
        from(a in Lightning.Credentials.Audit.base_query(),
          where: a.item_id == ^credential.id,
          select: {a.event, type(a.changes, :map)}
        )

      assert Lightning.Repo.all(audit_events_query) == []

      view = open(conn)

      send_event(
        view,
        "update_credential",
        raw_values(%{
          "id" => credential.id,
          "name" => "my-credential",
          "schema" => "http",
          "projectIds" => [],
          "environments" => [
            %{
              "name" => "main",
              "previousName" => "main",
              "body" => ~s({"username": "test", "password": "test"}),
              "signInId" => nil
            }
          ]
        })
      )

      assert_reply(view, %{})

      assert Repo.preload(credential, :projects, force: true).projects == []

      audit_events = Lightning.Repo.all(audit_events_query)

      assert Enum.count(audit_events) == 2

      assert {"updated", _changes} =
               Enum.find(audit_events, fn {event, _changes} ->
                 event == "updated"
               end)

      assert {"removed_from_project", _changes} =
               Enum.find(audit_events, fn {event, _changes} ->
                 event == "removed_from_project"
               end)
    end

    test "tells the page which workflows use the credential in each project",
         %{
           conn: conn,
           user: user
         } do
      credential =
        credential_with_body(
          user,
          %{name: "my-credential", schema: "http"},
          %{"username" => "test", "password" => "test"}
        )

      project =
        insert(:project, project_users: [build(:project_user, user: user)])

      project_credential =
        insert(:project_credential, project: project, credential: credential)

      workflow_with_credential_1 =
        insert(:simple_workflow, project: project)
        |> tap(fn %{jobs: [job_1 | _]} ->
          job_1
          |> Ecto.Changeset.change(%{
            project_credential_id: project_credential.id
          })
          |> Lightning.Repo.update!()
        end)
        |> with_snapshot()

      workflow_with_credential_2 =
        insert(:simple_workflow, project: project)
        |> tap(fn %{jobs: [job_1 | _]} ->
          job_1
          |> Ecto.Changeset.change(%{
            project_credential_id: project_credential.id
          })
          |> Lightning.Repo.update!()
        end)
        |> with_snapshot()

      _workflow_without_credential =
        insert(:simple_workflow, project: project) |> with_snapshot()

      another_project =
        insert(:project, project_users: [build(:project_user, user: user)])

      insert(:project_credential,
        project: another_project,
        credential: credential
      )

      view = open(conn)

      # The page warns before revoking a project from the workflows it's
      # given here; the dialog itself is the design system's.
      assert [%{"projects" => projects}] =
               Enum.filter(
                 props(view)["credentials"],
                 &(&1["id"] == credential.id)
               )

      workflows_using = Map.new(projects, &{&1["id"], &1["workflowsUsing"]})

      assert Enum.sort(workflows_using[project.id]) ==
               Enum.sort([
                 workflow_with_credential_1.name,
                 workflow_with_credential_2.name
               ])

      assert workflows_using[another_project.id] == []
    end

    test "users can add and remove existing project credentials successfully", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project, project_users: [build(:project_user, user: user)])

      credential =
        credential_with_body(
          user,
          %{name: "my-credential", schema: "http"},
          %{"username" => "test", "password" => "test"}
        )

      insert(:project_credential, project: project, credential: credential)

      view = open(conn)

      save = fn project_ids ->
        send_event(
          view,
          "update_credential",
          raw_values(%{
            "id" => credential.id,
            "name" => "my-credential",
            "schema" => "http",
            "projectIds" => project_ids,
            "environments" => [
              %{
                "name" => "main",
                "previousName" => "main",
                "body" => ~s({"username": "test", "password": "test"}),
                "signInId" => nil
              }
            ]
          })
        )

        assert_reply(view, %{})

        credential
        |> Repo.preload(:projects, force: true)
        |> Map.fetch!(:projects)
        |> Enum.map(& &1.id)
      end

      # Adding a project it already has doesn't break anything
      assert save.([project.id, project.id]) == [project.id]

      # Remove it, then add it back
      assert save.([]) == []
      assert save.([project.id]) == [project.id]
    end
  end

  describe "Authorizing an oauth credential" do
    setup do
      {:ok,
       token: %{
         "access_token" => "ya29.a0AVvZ",
         "refresh_token" => "1//03vpp6Li",
         "expires_at" => DateTime.to_unix(DateTime.utc_now()) + 3600,
         "token_type" => "Bearer",
         "id_token" => "eyJhbGciO",
         "scope" => "scope1 scope2"
       }}
    end

    test "renders error when revocation fails",
         %{
           conn: conn,
           user: user,
           token: token
         } do
      oauth_client = insert(:oauth_client, user: user, userinfo_endpoint: nil)

      # Make the token expired so it needs refresh
      expired_token =
        Map.put(token, "expires_at", DateTime.to_unix(DateTime.utc_now()) - 3600)

      credential =
        insert(:credential,
          user: user,
          schema: "oauth",
          oauth_client: oauth_client
        )
        |> with_body(%{
          name: "main",
          body: expired_token
        })

      Mox.stub(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn env,
                                                                       _opts ->
        case env.url do
          "http://example.com/oauth2/revoke" ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: Jason.encode!(%{})
             }}

          "http://example.com/oauth2/token" ->
            # Return 401 to simulate invalid token
            {:ok,
             %Tesla.Env{
               status: 401,
               body: Jason.encode!(%{"error" => "invalid_token"})
             }}
        end
      end)

      view = open(conn)

      send_event(view, "load_credential_secrets", %{"id" => credential.id})

      # The page asks the user to sign in again.
      assert_reply(view, %{
        environments: [%{name: "main", oauth: %{status: "reauthorize"}}]
      })
    end

    test "renders reauthorize prompt when refresh token is revoked",
         %{
           conn: conn,
           user: user,
           token: token
         } do
      oauth_client = insert(:oauth_client, user: user, userinfo_endpoint: nil)

      expired_token =
        Map.put(token, "expires_at", DateTime.to_unix(DateTime.utc_now()) - 3600)

      credential =
        insert(:credential,
          user: user,
          schema: "oauth",
          oauth_client: oauth_client
        )
        |> with_body(%{
          name: "main",
          body: expired_token
        })

      Mox.stub(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn env,
                                                                       _opts ->
        case env.url do
          "http://example.com/oauth2/revoke" ->
            {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{})}}

          "http://example.com/oauth2/token" ->
            {:ok,
             %Tesla.Env{
               status: 400,
               body:
                 Jason.encode!(%{
                   "error" => "invalid_grant",
                   "error_description" => "Token has been expired or revoked."
                 })
             }}
        end
      end)

      view = open(conn)

      send_event(view, "load_credential_secrets", %{"id" => credential.id})

      assert_reply(view, %{
        environments: [%{name: "main", oauth: %{status: "reauthorize"}}]
      })

      # The stored token is left as it was.
      assert bodies(credential) == %{"main" => expired_token}
    end

    test "a failed refresh with a 5xx keeps the transient provider-error message",
         %{conn: conn, user: user, token: token} do
      oauth_client = insert(:oauth_client, user: user, userinfo_endpoint: nil)

      expired_token =
        Map.put(token, "expires_at", DateTime.to_unix(DateTime.utc_now()) - 3600)

      credential =
        insert(:credential,
          user: user,
          schema: "oauth",
          oauth_client: oauth_client
        )
        |> with_body(%{name: "main", body: expired_token})

      Mox.stub(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn env,
                                                                       _opts ->
        case env.url do
          "http://example.com/oauth2/revoke" ->
            {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{})}}

          "http://example.com/oauth2/token" ->
            {:ok,
             %Tesla.Env{
               status: 503,
               body: Jason.encode!(%{"error" => "server_error"})
             }}
        end
      end)

      view = open(conn)

      send_event(view, "load_credential_secrets", %{"id" => credential.id})

      # The provider couldn't be reached: not a reason to sign in again.
      assert_reply(view, %{
        environments: [%{name: "main", oauth: %{status: "unavailable"}}]
      })
    end

    test "a code-exchange failure is not treated as a refresh reauthorization",
         %{conn: conn, user: user} do
      insert(:project, project_users: [%{user: user, role: :owner}])

      oauth_client =
        insert(:oauth_client,
          user: user,
          mandatory_scopes: "",
          optional_scopes: ""
        )

      Mox.stub(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn env,
                                                                       _opts ->
        case env.url do
          "http://example.com/oauth2/token" ->
            {:ok,
             %Tesla.Env{
               status: 400,
               body:
                 Jason.encode!(%{
                   "error" => "invalid_grant",
                   "error_description" => "Bad authorization code."
                 })
             }}
        end
      end)

      view = open(conn)
      sign_in(view, oauth_client, %{"scopes" => []})

      assert [%{"signInId" => "s1", "error" => error, "userInfo" => nil}] =
               props(view)["oauthSignIns"]

      assert is_binary(error)
      refute error =~ "revoked"
    end
  end

  describe "generic oauth credential when flow fails" do
    setup do
      Mox.stub(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn env,
                                                                       _opts ->
        case env.url do
          "http://example.com/oauth2/revoke" ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: Jason.encode!(%{})
             }}

          "http://example.com/oauth2/token" ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body:
                 Jason.encode!(%{
                   "access_token" => "ya29.a0AVvZ",
                   "expires_at" => DateTime.to_unix(DateTime.utc_now()) + 3600,
                   "token_type" => "Bearer",
                   "id_token" => "eyJhbGciO",
                   "scope" => "scope1 scope2"
                 })
             }}

          "http://example.com/oauth2/userinfo" ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body:
                 Jason.encode!(%{
                   "picture" => "image.png",
                   "name" => "Test User"
                 })
             }}
        end
      end)

      :ok
    end

    test "When token doesn't have a refresh token, credential can't be saved", %{
      conn: conn,
      user: user
    } do
      insert(:project, project_users: [%{user: user, role: :owner}])

      oauth_client =
        insert(:oauth_client,
          user: user,
          mandatory_scopes: "",
          optional_scopes: ""
        )

      view = open(conn)
      sign_in(view, oauth_client, %{"scopes" => []})

      # Should show error state but not user info
      assert [%{"signInId" => "s1", "error" => error, "userInfo" => nil}] =
               props(view)["oauthSignIns"]

      assert error =~ "already connected"

      # Credential should not be created even if form is submitted
      send_event(
        view,
        "create_credential",
        oauth_values(oauth_client, "s1", %{
          "name" => "My Generic OAuth Credential"
        })
      )

      assert_reply(view, %{fieldErrors: %{"environments.main" => [_]}})
      assert Lightning.Credentials.list_credentials(user) == []
    end
  end

  describe "errors when creating generic oauth credentials" do
    test "error when fetching authorization code", %{conn: conn, user: user} do
      oauth_client = insert(:oauth_client, user: user)

      view = open(conn)

      sign_in(view, oauth_client, %{}, %{
        error: "failed fetching authorization code"
      })

      assert [%{"signInId" => "s1", "error" => error, "userInfo" => nil}] =
               props(view)["oauthSignIns"]

      assert error =~ "The authentication process with"
    end

    test "error when fetching token", %{conn: conn, user: user} do
      Mox.stub(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn env,
                                                                       _opts ->
        case env.url do
          "http://example.com/oauth2/revoke" ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: Jason.encode!(%{})
             }}

          "http://example.com/oauth2/token" ->
            {:ok,
             %Tesla.Env{
               status: 401,
               body: Jason.encode!(%{"error" => "invalid_client"})
             }}

          "http://example.com/oauth2/userinfo" ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body:
                 Jason.encode!(%{
                   "picture" => "image.png",
                   "name" => "Test User"
                 })
             }}
        end
      end)

      oauth_client = insert(:oauth_client, user: user)

      view = open(conn)
      sign_in(view, oauth_client)

      assert [%{"signInId" => "s1", "error" => error, "userInfo" => nil}] =
               props(view)["oauthSignIns"]

      assert error =~ "Your authorization with"
    end

    test "error when fetching userinfo", %{conn: conn, user: user} do
      Mox.stub(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn env,
                                                                       _opts ->
        case env.url do
          "http://example.com/oauth2/revoke" ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: Jason.encode!(%{})
             }}

          "http://example.com/oauth2/token" ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body:
                 Jason.encode!(%{
                   "access_token" => "ya29.a0AVvZ",
                   "refresh_token" => "1//03vpp6Li",
                   "expires_at" => DateTime.to_unix(DateTime.utc_now()) + 3600,
                   "token_type" => "Bearer",
                   "id_token" => "eyJhbGciO",
                   "scope" => "scope_1 scope_2"
                 })
             }}

          "http://example.com/oauth2/userinfo" ->
            {:ok,
             %Tesla.Env{
               status: 500,
               body: "Internal Server Error"
             }}
        end
      end)

      oauth_client =
        insert(:oauth_client,
          user: user,
          mandatory_scopes: "scope_1,scope_2",
          optional_scopes: ""
        )

      view = open(conn)
      sign_in(view, oauth_client)

      # Signed in, only without the account's name.
      assert [%{"signInId" => "s1", "error" => nil, "userInfo" => nil}] =
               props(view)["oauthSignIns"]

      send_event(
        view,
        "create_credential",
        oauth_values(oauth_client, "s1", %{
          "name" => "My Generic OAuth Credential"
        })
      )

      assert_reply(view, %{})

      assert [credential] = Lightning.Credentials.list_credentials(user)

      assert %{"main" => %{"access_token" => "ya29.a0AVvZ"}} =
               bodies(credential)
    end
  end

  describe "generic oauth credential offline_access handling" do
    # The scope boxes and the sign-in window are the design system's; the
    # server checks what the provider granted against what was asked for.

    test "ignores offline_access in selected scopes when validating", %{
      conn: conn,
      user: user
    } do
      oauth_client =
        insert(:oauth_client,
          user: user,
          mandatory_scopes: "read,write",
          optional_scopes: "offline_access"
        )

      stub_provider(oauth_client, {200, %{token() | "scope" => "read write"}})
      view = open(conn)

      sign_in(view, oauth_client, %{
        "scopes" => ["read", "write", "offline_access"]
      })

      assert [%{"error" => nil, "userInfo" => %{"name" => "Ada"}}] =
               props(view)["oauthSignIns"]

      assert send_event(
               view,
               "create_credential",
               oauth_values(oauth_client, "s1", %{"name" => "Test Credential"})
             ) =~ "Credential created successfully"

      assert [%{name: "Test Credential"}] = Credentials.list_credentials(user)
    end

    test "validates other missing scopes while ignoring offline_access", %{
      conn: conn,
      user: user
    } do
      oauth_client =
        insert(:oauth_client,
          user: user,
          mandatory_scopes: "read,write",
          optional_scopes: "admin,offline_access"
        )

      stub_provider(oauth_client, {200, %{token() | "scope" => "read"}})
      view = open(conn)

      sign_in(view, oauth_client, %{
        "scopes" => ["read", "write", "admin", "offline_access"]
      })

      assert [%{"error" => error, "userInfo" => nil}] =
               props(view)["oauthSignIns"]

      # The missing scopes are named, offline_access isn't among them
      assert error =~ "write"
      refute error =~ "offline_access"

      send_event(
        view,
        "create_credential",
        oauth_values(oauth_client, "s1", %{"name" => "Test Credential"})
      )

      assert_reply(view, %{fieldErrors: %{"environments.main" => [_]}})
      assert Credentials.list_credentials(user) == []

      # The user may sign in again
      send_event(view, "authorize_oauth", %{
        "formId" => "form-1",
        "signInId" => "s2",
        "credentialId" => nil,
        "oauthClientId" => oauth_client.id,
        "scopes" => ["read", "write"],
        "environment" => "main"
      })

      assert_reply(view, %{authorizeUrl: _})
    end

    test "handles offline_access with different casing", %{
      conn: conn,
      user: user
    } do
      oauth_client =
        insert(:oauth_client,
          user: user,
          mandatory_scopes: "read",
          optional_scopes: "OFFLINE_ACCESS"
        )

      stub_provider(oauth_client, {200, %{token() | "scope" => "read"}})
      view = open(conn)

      assert [%{"optionalScopes" => optional}] = props(view)["oauthClients"]
      assert "offline_access" in Enum.map(optional, &String.downcase/1)

      sign_in(view, oauth_client, %{"scopes" => ["read" | optional]})

      assert [%{"error" => nil, "userInfo" => %{"name" => "Ada"}}] =
               props(view)["oauthSignIns"]
    end

    test "handles case where offline_access is in granted scopes", %{
      conn: conn,
      user: user
    } do
      oauth_client =
        insert(:oauth_client,
          user: user,
          mandatory_scopes: "read,write",
          optional_scopes: "offline_access"
        )

      stub_provider(
        oauth_client,
        {200, %{token() | "scope" => "read write offline_access"}}
      )

      view = open(conn)

      sign_in(view, oauth_client, %{
        "scopes" => ["read", "write", "offline_access"]
      })

      assert [%{"error" => nil, "userInfo" => %{"name" => "Ada"}}] =
               props(view)["oauthSignIns"]
    end
  end

  describe "transfer credential modal" do
    # The modal and its submit button are the design system's; the server
    # validates the receiver when the page sends the transfer.

    setup %{conn: conn} do
      owner = insert(:user)
      project = build(:project) |> with_project_user(owner, :owner) |> insert()

      credential =
        insert(:credential,
          user: owner,
          project_credentials: [%{project_id: project.id}]
        )

      conn = log_in_user(conn, owner)
      view = open(conn)

      transfer = fn email ->
        send_event(view, "transfer_credential", %{
          "id" => credential.id,
          "receiverEmail" => email
        })
      end

      %{
        owner: owner,
        project: project,
        credential: credential,
        view: view,
        transfer: transfer
      }
    end

    test "validates required email", %{
      view: view,
      credential: credential,
      transfer: transfer
    } do
      transfer.("")

      assert_reply(view, %{
        fieldErrors: %{"receiverEmail" => ["This field can't be blank."]}
      })

      refute Repo.reload(credential).transfer_status
    end

    test "validates email format", %{
      view: view,
      credential: credential,
      transfer: transfer
    } do
      transfer.("invalid-email")

      assert_reply(view, %{
        fieldErrors: %{"receiverEmail" => ["Email address not valid."]}
      })

      refute Repo.reload(credential).transfer_status
    end

    test "validates receiver exists", %{
      view: view,
      credential: credential,
      transfer: transfer
    } do
      transfer.("nonexistent@example.com")

      assert_reply(view, %{
        fieldErrors: %{"receiverEmail" => ["User does not exist"]}
      })

      refute Repo.reload(credential).transfer_status
    end

    test "validates cannot transfer to self", %{
      view: view,
      owner: owner,
      credential: credential,
      transfer: transfer
    } do
      transfer.(owner.email)

      assert_reply(view, %{
        fieldErrors: %{
          "receiverEmail" => ["You cannot transfer a credential to yourself"]
        }
      })

      refute Repo.reload(credential).transfer_status
    end

    test "validates receiver has project access", %{
      view: view,
      credential: credential,
      transfer: transfer
    } do
      receiver = insert(:user)
      transfer.(receiver.email)

      assert_reply(view, %{fieldErrors: %{"receiverEmail" => [message]}})
      assert message =~ "User doesn't have access to these projects"

      refute Repo.reload(credential).transfer_status
    end

    test "initiates transfer for valid receiver", %{
      view: view,
      project: project,
      credential: credential,
      transfer: transfer
    } do
      receiver = insert(:user)
      insert(:project_user, project: project, user: receiver)

      assert transfer.(receiver.email) =~ "Credential transfer initiated"

      assert_email_sent(
        to: Swoosh.Email.Recipient.format(credential.user),
        subject: "Transfer #{credential.name} to #{receiver.first_name}"
      )

      assert Repo.reload(credential).transfer_status == :pending
      assert [%{"transferStatus" => "pending"}] = props(view)["credentials"]
    end
  end

  describe "revoke credential transfer modal" do
    # The modal is the design system's, drawn from the row's transfer status.

    setup %{conn: conn} do
      owner = insert(:user)
      project = build(:project) |> with_project_user(owner, :owner) |> insert()

      credential =
        insert(:credential,
          user: owner,
          project_credentials: [%{project_id: project.id}],
          transfer_status: :pending
        )

      conn = log_in_user(conn, owner)
      view = open(conn)

      %{
        owner: owner,
        project: project,
        credential: credential,
        view: view
      }
    end

    test "revokes transfer successfully", %{
      view: view,
      credential: credential
    } do
      assert send_event(view, "revoke_credential_transfer", %{
               "id" => credential.id
             }) =~ "Transfer revoked successfully"

      updated_credential =
        Repo.get(Lightning.Credentials.Credential, credential.id)

      assert is_nil(updated_credential.transfer_status)
      assert [%{"transferStatus" => nil}] = props(view)["credentials"]
    end

    test "handles revoke failure gracefully", %{
      view: view,
      credential: credential
    } do
      # Force a failure by deleting the credential first
      Repo.delete!(credential)

      send_event(view, "revoke_credential_transfer", %{"id" => credential.id})

      assert_reply(view, %{error: error})
      assert error == refused()
    end
  end

  describe "credential type picker modal" do
    # The picker and each type's icon are the design system's, drawn from
    # the types the server offers.

    test "offers the adaptors with a credential schema as types", %{conn: conn} do
      keys = Enum.map(props(open(conn))["credentialTypes"], & &1["key"])

      for adaptor <- ["postgresql", "dhis2", "http"] do
        assert adaptor in keys
      end
    end

    test "omits a deprecated adaptor from the type options", %{conn: conn} do
      insert(:adaptor,
        name: "deprecated-adaptor",
        deprecated: true,
        schema_data: ~s({"type":"object"})
      )

      Lightning.AdaptorTestHelpers.prime_packages_cache()

      keys = Enum.map(props(open(conn))["credentialTypes"], & &1["key"])

      assert "http" in keys
      refute "deprecated-adaptor" in keys
    end

    test "omits an adaptor with no configuration schema", %{conn: conn} do
      insert(:adaptor, name: "@openfn/language-no-schema", schema_data: nil)

      Lightning.AdaptorTestHelpers.prime_packages_cache()

      keys = Enum.map(props(open(conn))["credentialTypes"], & &1["key"])

      assert "http" in keys
      refute "no-schema" in keys
    end
  end

  describe "generic oauth credential" do
    setup do
      Mox.stub(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn env,
                                                                       _opts ->
        case env.url do
          "http://example.com/oauth2/revoke" ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body: Jason.encode!(%{})
             }}

          "http://example.com/oauth2/token" ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body:
                 Jason.encode!(%{
                   "access_token" => "ya29.a0AVvZ",
                   "refresh_token" => "1//03vpp6Li",
                   "expires_at" => DateTime.to_unix(DateTime.utc_now()) + 3600,
                   "token_type" => "Bearer",
                   "id_token" => "eyJhbGciO",
                   "scope" => "scope_1 scope_2"
                 })
             }}

          "http://example.com/oauth2/userinfo" ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body:
                 Jason.encode!(%{
                   "picture" => "image.png",
                   "name" => "Test User"
                 })
             }}
        end
      end)

      :ok
    end

    test "allow the user to create a new generic oauth credential", %{
      conn: conn,
      user: user
    } do
      [project_1, _project_2, project_3] =
        insert_list(3, :project, project_users: [%{user: user, role: :owner}])

      oauth_client =
        insert(:oauth_client,
          user: user,
          mandatory_scopes: "",
          optional_scopes: ""
        )

      view = open(conn)
      sign_in(view, oauth_client)

      assert [%{"signInId" => "s1", "userInfo" => %{"name" => "Test User"}}] =
               props(view)["oauthSignIns"]

      assert send_event(
               view,
               "create_credential",
               oauth_values(oauth_client, "s1", %{
                 "name" => "My Generic OAuth Credential",
                 "projectIds" => [project_1.id, project_3.id]
               })
             ) =~ "Credential created successfully"

      credential =
        Lightning.Credentials.list_credentials(user)
        |> List.first()
        |> Repo.preload([:credential_bodies, :project_credentials])

      assert MapSet.new(credential.project_credentials, & &1.project_id) ==
               MapSet.new([project_1.id, project_3.id])

      # Get the main environment body
      main_body = Enum.find(credential.credential_bodies, &(&1.name == "main"))

      assert %{
               "access_token" => "ya29.a0AVvZ",
               "refresh_token" => "1//03vpp6Li",
               "expires_at" => _,
               "scope" => "scope_1 scope_2"
             } = main_body.body
    end

    test "allow the user to edit an oauth credential", %{
      conn: conn,
      user: user
    } do
      [project_1, project_2, project_3] =
        insert_list(3, :project, project_users: [%{user: user, role: :owner}])

      oauth_client = insert(:oauth_client, user: user, userinfo_endpoint: nil)

      # Create a valid, non-expired token
      expires_at = DateTime.to_unix(DateTime.utc_now()) + 3600

      credential =
        insert(:credential,
          name: "OAuth credential",
          oauth_client: oauth_client,
          user: user,
          schema: "oauth",
          project_credentials: [
            %{project: project_1},
            %{project: project_2},
            %{project: project_3}
          ]
        )
        |> with_body(%{
          name: "main",
          body: %{
            "access_token" => "test_access_token",
            "refresh_token" => "test_refresh_token",
            "token_type" => "Bearer",
            "expires_at" => expires_at,
            "scope" =>
              String.split(oauth_client.mandatory_scopes, ",") |> Enum.join(" ")
          }
        })

      view = open(conn)

      assert send_event(
               view,
               "update_credential",
               oauth_values(oauth_client, nil, %{
                 "id" => credential.id,
                 "name" => "My Generic OAuth Credential",
                 "projectIds" => [project_2.id, project_3.id],
                 "environments" => [
                   %{
                     "name" => "main",
                     "previousName" => "main",
                     "body" => "",
                     "signInId" => nil
                   }
                 ]
               })
             ) =~ "Credential updated successfully"

      credential =
        credential
        |> Repo.reload!()
        |> Repo.preload(:project_credentials)

      assert credential.name == "My Generic OAuth Credential"

      assert MapSet.new(credential.project_credentials, & &1.project_id) ==
               MapSet.new([project_2.id, project_3.id])

      # Without a new sign-in, the stored token is kept.
      assert %{"main" => %{"access_token" => "test_access_token"}} =
               bodies(credential)
    end

    test "a new credential starts its first sign-in with the client's scopes",
         %{
           conn: conn,
           user: user
         } do
      oauth_client = insert(:oauth_client, user: user)

      view = open(conn)

      # Whether to ask for a new sign-in is the design system's: a new
      # credential has no stored scopes to compare with, so the page gets the
      # client's scopes and starts the first sign-in with those ticked.
      assert [
               %{
                 "mandatoryScopes" => ["scope_1", "scope_2"],
                 "optionalScopes" => optional
               }
             ] = props(view)["oauthClients"]

      send_event(view, "authorize_oauth", %{
        "formId" => "form-1",
        "signInId" => "s1",
        "credentialId" => nil,
        "oauthClientId" => oauth_client.id,
        "scopes" => optional,
        "environment" => "main"
      })

      assert_reply(view, %{authorizeUrl: url})
      assert String.starts_with?(url, oauth_client.authorization_endpoint)
    end

    test "the edit form gets the stored token's scopes to compare a new pick with",
         %{
           conn: conn,
           user: user
         } do
      oauth_client = insert(:oauth_client, user: user)

      credential =
        insert(:credential,
          name: "my-credential",
          schema: "oauth",
          user: user,
          oauth_client: oauth_client
        )
        |> with_body(%{
          name: "main",
          body: %{
            "access_token" => "access_token",
            "refresh_token" => "refresh_token",
            "expires_at" =>
              Timex.now() |> Timex.shift(days: 4) |> DateTime.to_unix(),
            "scope" =>
              String.split(oauth_client.mandatory_scopes, ",")
              |> Enum.join(" ")
          }
        })

      view = open(conn)

      # The page compares the ticked scopes with the stored token's, and
      # asks for a new sign-in when they differ; that part is the design
      # system's.
      send_event(view, "load_credential_secrets", %{"id" => credential.id})

      assert_reply(view, %{
        environments: [
          %{name: "main", oauth: %{scopes: ["scope_1", "scope_2"]}}
        ]
      })

      send_event(view, "authorize_oauth", %{
        "formId" => "form-1",
        "signInId" => "s1",
        "credentialId" => credential.id,
        "oauthClientId" => oauth_client.id,
        "scopes" => String.split(oauth_client.optional_scopes, ","),
        "environment" => "main"
      })

      assert_reply(view, %{authorizeUrl: url})

      assert %{"scope" => "scope_1 scope_2 scope_3 scope_4"} =
               url |> URI.parse() |> Map.fetch!(:query) |> URI.decode_query()
    end

    test "correctly renders a valid existing token", %{
      conn: conn,
      user: user
    } do
      oauth_client = insert(:oauth_client, user: user)
      expires_at = DateTime.to_unix(DateTime.utc_now()) + 3600

      credential =
        insert(:credential,
          user: user,
          schema: "oauth",
          oauth_client: oauth_client
        )
        |> with_body(%{
          name: "main",
          body: %{
            "access_token" => "ya29.a0AVvZ...",
            "refresh_token" => "1//03vpp6Li...",
            "expires_at" => expires_at,
            "token_type" => "Bearer",
            "scope" =>
              String.split(oauth_client.mandatory_scopes, ",")
              |> Enum.join(" ")
          }
        })

      view = open(conn)

      send_event(view, "load_credential_secrets", %{"id" => credential.id})

      assert_reply(view, %{
        environments: [
          %{
            name: "main",
            body: "",
            oauth: %{status: "ready", userInfo: %{name: "Test User"}}
          }
        ]
      })
    end

    test "renewing an expired but valid token", %{
      user: user,
      conn: conn
    } do
      oauth_client =
        insert(:oauth_client,
          user: user,
          mandatory_scopes: "scope_1,scope_2",
          optional_scopes: ""
        )

      expires_at = DateTime.to_unix(DateTime.utc_now()) - 50

      credential =
        insert(:credential,
          user: user,
          schema: "oauth",
          oauth_client_id: oauth_client.id
        )
        |> with_body(%{
          name: "main",
          body: %{
            "access_token" => "ya29.a0AVvZ...",
            "refresh_token" => "1//03vpp6Li...",
            "expires_at" => expires_at,
            "scope" =>
              String.split(oauth_client.mandatory_scopes, ",")
              |> Enum.join(" ")
          }
        })

      view = open(conn)

      send_event(view, "load_credential_secrets", %{"id" => credential.id})

      assert_reply(view, %{
        environments: [
          %{oauth: %{status: "ready", userInfo: %{name: "Test User"}}}
        ]
      })

      # Opening it refreshes the token and saves it, as a run would.
      assert %{"main" => %{"access_token" => "ya29.a0AVvZ"}} =
               bodies(credential)
    end

    test "when oauth client is deleted, its credentials have no client and need signing in again",
         %{user: user, conn: conn} do
      oauth_client = insert(:oauth_client, user: user)

      credential =
        insert(:credential,
          name: "My OAuth Credential",
          schema: "oauth",
          oauth_client: oauth_client,
          user: user
        )
        |> with_body(%{
          name: "main",
          body: %{
            "access_token" => "test_access_token",
            "refresh_token" => "test_refresh_token",
            "token_type" => "bearer",
            "expires_in" => 3600
          }
        })

      view = open(conn)

      assert [%{"name" => "My OAuth Credential", "oauthClient" => %{"id" => id}}] =
               props(view)["credentials"]

      assert id == oauth_client.id

      # Now lets delete the oauth client
      Repo.delete!(oauth_client)

      view = open(conn)

      # The page warns about an OAuth credential without its client.
      assert [
               %{
                 "name" => "My OAuth Credential",
                 "schema" => "oauth",
                 "oauthClient" => nil
               }
             ] = props(view)["credentials"]

      send_event(view, "load_credential_secrets", %{"id" => credential.id})

      assert_reply(view, %{
        environments: [%{oauth: %{status: "reauthorize", userInfo: nil}}]
      })
    end

    test "offers the client's optional scopes and asks only for the ones picked",
         %{
           user: user,
           conn: conn
         } do
      oauth_client = insert(:oauth_client, user: user)
      view = open(conn)

      # The pick list itself is the design system's; it lists these.
      assert [%{"optionalScopes" => scopes_to_choose}] =
               props(view)["oauthClients"]

      assert scopes_to_choose == String.split(oauth_client.optional_scopes, ",")

      not_chosen_scopes =
        ~W(wave_api api custom_permissions id profile email address)

      scopes_in_url = fn sign_in_id, scopes ->
        send_event(view, "authorize_oauth", %{
          "formId" => "form-1",
          "signInId" => sign_in_id,
          "credentialId" => nil,
          "oauthClientId" => oauth_client.id,
          "scopes" => scopes,
          "environment" => "main"
        })

        assert_reply(view, %{authorizeUrl: url})

        url
        |> URI.parse()
        |> Map.fetch!(:query)
        |> URI.decode_query()
        |> Map.fetch!("scope")
        |> String.split(" ")
      end

      scopes = scopes_in_url.("s1", scopes_to_choose)

      assert Enum.all?(scopes_to_choose, &(&1 in scopes))
      refute Enum.any?(not_chosen_scopes, &(&1 in scopes))

      # Unselecting one of the already selected scopes leaves it out of the
      # authorization url
      [scope_to_unselect | rest] = scopes_to_choose

      refute scope_to_unselect in scopes_in_url.("s2", rest)
    end
  end

  describe "credential propagation to sandboxes" do
    test "creating credential with project propagates to descendant sandboxes",
         %{
           conn: conn,
           user: user
         } do
      # Create parent project
      parent =
        insert(:project, project_users: [%{user: user, role: :owner}])

      # Create sandbox hierarchy
      {:ok, sandbox_1} =
        Lightning.Projects.provision_sandbox(parent, user, %{
          name: "sandbox-1",
          env: "staging"
        })

      {:ok, sandbox_2} =
        Lightning.Projects.provision_sandbox(sandbox_1, user, %{
          name: "sandbox-2",
          env: "dev"
        })

      # Create the credential, shared with the parent project
      view = open(conn)

      assert send_event(
               view,
               "create_credential",
               raw_values(%{
                 "name" => "Test Propagation Credential",
                 "projectIds" => [parent.id],
                 "environments" => [
                   %{
                     "name" => "main",
                     "previousName" => nil,
                     "body" => Jason.encode!(%{"key" => "value"}),
                     "signInId" => nil
                   }
                 ]
               })
             ) =~ "Credential created successfully"

      # Verify credential was created
      credential =
        Repo.get_by(Credential, name: "Test Propagation Credential")

      assert credential

      # Verify credential is accessible in all projects
      parent_has_credential =
        Repo.one(
          from pc in Lightning.Projects.ProjectCredential,
            where:
              pc.project_id == ^parent.id and
                pc.credential_id == ^credential.id
        )

      sandbox_1_has_credential =
        Repo.one(
          from pc in Lightning.Projects.ProjectCredential,
            where:
              pc.project_id == ^sandbox_1.id and
                pc.credential_id == ^credential.id
        )

      sandbox_2_has_credential =
        Repo.one(
          from pc in Lightning.Projects.ProjectCredential,
            where:
              pc.project_id == ^sandbox_2.id and
                pc.credential_id == ^credential.id
        )

      assert parent_has_credential
      assert sandbox_1_has_credential
      assert sandbox_2_has_credential
    end

    test "updating credential to add project propagates to that project's sandboxes",
         %{
           conn: conn,
           user: user
         } do
      # Create a credential first
      credential =
        insert(:credential,
          name: "Update Test Credential",
          schema: "http",
          body: %{"username" => "test", "password" => "test"},
          user: user
        )

      # Create parent project and sandboxes
      parent =
        insert(:project, project_users: [%{user: user, role: :owner}])

      {:ok, sandbox_1} =
        Lightning.Projects.provision_sandbox(parent, user, %{
          name: "sandbox-1",
          env: "staging"
        })

      {:ok, sandbox_2} =
        Lightning.Projects.provision_sandbox(sandbox_1, user, %{
          name: "sandbox-2",
          env: "dev"
        })

      # Save the credential with the parent project added
      view = open(conn)

      assert send_event(
               view,
               "update_credential",
               raw_values(%{
                 "id" => credential.id,
                 "name" => "Update Test Credential",
                 "schema" => "http",
                 "projectIds" => [parent.id],
                 "environments" => [
                   %{
                     "name" => "main",
                     "previousName" => "main",
                     "body" =>
                       Jason.encode!(%{
                         "username" => "test",
                         "password" => "test"
                       }),
                     "signInId" => nil
                   }
                 ]
               })
             ) =~ "Credential updated successfully"

      # Verify credential was propagated to all descendants
      parent_has_credential =
        Repo.one(
          from pc in Lightning.Projects.ProjectCredential,
            where:
              pc.project_id == ^parent.id and
                pc.credential_id == ^credential.id
        )

      sandbox_1_has_credential =
        Repo.one(
          from pc in Lightning.Projects.ProjectCredential,
            where:
              pc.project_id == ^sandbox_1.id and
                pc.credential_id == ^credential.id
        )

      sandbox_2_has_credential =
        Repo.one(
          from pc in Lightning.Projects.ProjectCredential,
            where:
              pc.project_id == ^sandbox_2.id and
                pc.credential_id == ^credential.id
        )

      assert parent_has_credential
      assert sandbox_1_has_credential
      assert sandbox_2_has_credential
    end

    test "credential propagates to branching sandbox hierarchy", %{
      conn: conn,
      user: user
    } do
      # Create parent project
      parent =
        insert(:project, project_users: [%{user: user, role: :owner}])

      # Create branching structure
      {:ok, sandbox_a} =
        Lightning.Projects.provision_sandbox(parent, user, %{
          name: "sandbox-a",
          env: "staging"
        })

      {:ok, sandbox_b} =
        Lightning.Projects.provision_sandbox(parent, user, %{
          name: "sandbox-b",
          env: "dev"
        })

      {:ok, sandbox_a1} =
        Lightning.Projects.provision_sandbox(sandbox_a, user, %{
          name: "sandbox-a1",
          env: "test"
        })

      # Create credential with parent project
      view = open(conn)

      send_event(
        view,
        "create_credential",
        raw_values(%{
          "name" => "Branching Test Credential",
          "projectIds" => [parent.id]
        })
      )

      credential =
        Repo.get_by(Credential, name: "Branching Test Credential")

      # Verify all branches have access
      sandbox_ids = [parent.id, sandbox_a.id, sandbox_b.id, sandbox_a1.id]

      project_credentials =
        Repo.all(
          from pc in Lightning.Projects.ProjectCredential,
            where:
              pc.credential_id == ^credential.id and
                pc.project_id in ^sandbox_ids,
            select: pc.project_id
        )

      assert length(project_credentials) == 4

      assert MapSet.equal?(
               MapSet.new(project_credentials),
               MapSet.new(sandbox_ids)
             )
    end

    test "credential propagates through deep hierarchy (4+ levels)", %{
      conn: conn,
      user: user
    } do
      # Create deep hierarchy
      parent =
        insert(:project, project_users: [%{user: user, role: :owner}])

      {:ok, level_1} =
        Lightning.Projects.provision_sandbox(parent, user, %{
          name: "level-1",
          env: "staging"
        })

      {:ok, level_2} =
        Lightning.Projects.provision_sandbox(level_1, user, %{
          name: "level-2",
          env: "dev"
        })

      {:ok, level_3} =
        Lightning.Projects.provision_sandbox(level_2, user, %{
          name: "level-3",
          env: "test"
        })

      {:ok, level_4} =
        Lightning.Projects.provision_sandbox(level_3, user, %{
          name: "level-4",
          env: "local"
        })

      # Create credential, shared with the parent project
      view = open(conn)

      send_event(
        view,
        "create_credential",
        raw_values(%{
          "name" => "Deep Hierarchy Credential",
          "projectIds" => [parent.id]
        })
      )

      credential =
        Repo.get_by(Credential, name: "Deep Hierarchy Credential")

      # Verify all levels have access
      all_project_ids = [
        parent.id,
        level_1.id,
        level_2.id,
        level_3.id,
        level_4.id
      ]

      project_credentials =
        Repo.all(
          from pc in Lightning.Projects.ProjectCredential,
            where:
              pc.credential_id == ^credential.id and
                pc.project_id in ^all_project_ids,
            select: pc.project_id
        )

      assert length(project_credentials) == 5

      assert MapSet.equal?(
               MapSet.new(project_credentials),
               MapSet.new(all_project_ids)
             )
    end

    test "multiple credentials propagate independently to same sandbox hierarchy",
         %{
           conn: conn,
           user: user
         } do
      # Create parent and sandbox
      parent =
        insert(:project, project_users: [%{user: user, role: :owner}])

      {:ok, sandbox} =
        Lightning.Projects.provision_sandbox(parent, user, %{
          name: "sandbox",
          env: "staging"
        })

      view = open(conn)

      # Create first credential
      send_event(
        view,
        "create_credential",
        raw_values(%{"name" => "First Credential", "projectIds" => [parent.id]})
      )

      # Create second credential
      send_event(
        view,
        "create_credential",
        raw_values(%{
          "formId" => "form-2",
          "name" => "Second Credential",
          "projectIds" => [parent.id]
        })
      )

      # Verify both credentials are in parent and sandbox
      cred1 = Repo.get_by(Credential, name: "First Credential")
      cred2 = Repo.get_by(Credential, name: "Second Credential")

      parent_credentials =
        Repo.all(
          from pc in Lightning.Projects.ProjectCredential,
            where:
              pc.project_id == ^parent.id and
                pc.credential_id in [^cred1.id, ^cred2.id],
            select: pc.credential_id
        )

      sandbox_credentials =
        Repo.all(
          from pc in Lightning.Projects.ProjectCredential,
            where:
              pc.project_id == ^sandbox.id and
                pc.credential_id in [^cred1.id, ^cred2.id],
            select: pc.credential_id
        )

      assert length(parent_credentials) == 2
      assert length(sandbox_credentials) == 2

      assert MapSet.equal?(
               MapSet.new(parent_credentials),
               MapSet.new([cred1.id, cred2.id])
             )

      assert MapSet.equal?(
               MapSet.new(sandbox_credentials),
               MapSet.new([cred1.id, cred2.id])
             )
    end

    test "credential propagation is idempotent (no duplicate associations)", %{
      conn: conn,
      user: user
    } do
      # Create parent and sandbox
      parent =
        insert(:project, project_users: [%{user: user, role: :owner}])

      {:ok, sandbox} =
        Lightning.Projects.provision_sandbox(parent, user, %{
          name: "sandbox",
          env: "staging"
        })

      # Create credential and associate with parent twice
      view = open(conn)

      send_event(
        view,
        "create_credential",
        raw_values(%{
          "name" => "Idempotent Test Credential",
          "projectIds" => [parent.id]
        })
      )

      credential =
        Repo.get_by(Credential, name: "Idempotent Test Credential")

      # Save it again with the projects it lists, adding the parent again
      [%{"projects" => projects}] = props(view)["credentials"]
      project_ids = Enum.map(projects, & &1["id"]) ++ [parent.id]

      assert send_event(
               view,
               "update_credential",
               raw_values(%{
                 "id" => credential.id,
                 "name" => "Idempotent Test Credential",
                 "projectIds" => project_ids,
                 "environments" => [
                   %{
                     "name" => "main",
                     "previousName" => "main",
                     "body" => ~s({"a": 1}),
                     "signInId" => nil
                   }
                 ]
               })
             ) =~ "Credential updated successfully"

      # Verify no duplicate associations
      sandbox_credential_count =
        Repo.aggregate(
          from(pc in Lightning.Projects.ProjectCredential,
            where:
              pc.project_id == ^sandbox.id and
                pc.credential_id == ^credential.id
          ),
          :count
        )

      assert sandbox_credential_count == 1
    end
  end

  describe "credential environment tabs" do
    test "saves each environment's values separately", %{
      conn: conn,
      user: user
    } do
      view = open(conn)

      # Switching tabs is the design system's; each environment it sends is
      # saved with its own values.
      env = fn name, values ->
        %{
          "name" => name,
          "previousName" => nil,
          "body" => Jason.encode!(values),
          "signInId" => nil
        }
      end

      assert send_event(
               view,
               "create_credential",
               raw_values(%{
                 "name" => "Multi-env credential",
                 "schema" => "dhis2",
                 "environments" => [
                   env.("main", %{
                     username: "main_user",
                     password: "main_pass",
                     hostUrl: "http://main.example.com"
                   }),
                   env.("untitled", %{
                     username: "staging_user",
                     password: "staging_pass",
                     hostUrl: "http://staging.example.com"
                   })
                 ]
               })
             ) =~ "Credential created successfully"

      assert [credential] = Credentials.list_credentials(user)

      assert %{
               "main" => %{
                 "username" => "main_user",
                 "password" => "main_pass",
                 "hostUrl" => "http://main.example.com"
               },
               "untitled" => %{
                 "username" => "staging_user",
                 "password" => "staging_pass",
                 "hostUrl" => "http://staging.example.com"
               }
             } = bodies(credential)
    end
  end

  describe "when the adaptor catalogue cannot answer" do
    setup %{sup: sup} do
      Lightning.Repo.delete_all(Lightning.Adaptors.Catalogue.Adaptor)
      Cachex.clear(Lightning.Adaptors.Supervisor.cache_name(sup))

      :ok =
        Supervisor.terminate_child(
          sup,
          Lightning.Adaptors.Supervisor.highlander_name(sup)
        )

      :ok
    end

    test "offers no adaptor types until the catalogue answers, then offers them on the next load",
         %{conn: conn} do
      view = open(conn)

      # Only Raw JSON and the OAuth clients are offered.
      assert props(view)["credentialTypes"] == []

      seed_credential_schema("http")

      assert Enum.any?(
               props(open(conn))["credentialTypes"],
               &(&1["key"] == "http")
             )
    end

    test "the credential form offers a retry instead of crashing", %{
      conn: conn,
      user: user
    } do
      credential =
        insert(:credential, user: user, schema: "@openfn/language-http")

      view = open(conn)

      send_event(view, "load_credential_secrets", %{"id" => credential.id})
      assert_reply(view, %{environments: [%{name: "main"}]})

      send_event(view, "load_credential_schema", %{"key" => "http"})
      assert_reply(view, %{error: "Couldn't load adaptors. Please try again."})

      seed_credential_schema("http")

      send_event(view, "load_credential_schema", %{"key" => "http"})
      assert_reply(view, %{fields: fields})
      assert Enum.any?(fields, &(&1.key == "baseUrl"))
    end
  end
end
