defmodule LightningWeb.CredentialLiveTest do
  use LightningWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import LightningWeb.CredentialLiveHelpers

  import Lightning.BypassHelpers
  import Lightning.CredentialsFixtures
  import Lightning.Factories

  import Ecto.Query

  alias Lightning.Credentials

  @create_attrs %{
    name: "some name",
    body: Jason.encode!(%{"a" => 1})
  }

  @update_attrs %{
    name: "some updated name",
    body: "{\"a\":\"new_secret\"}"
  }

  @invalid_attrs %{name: "this won't work", body: nil}

  defp create_credential(%{user: user}) do
    credential = insert(:credential, user: user)
    %{credential: credential}
  end

  defp create_project_credential(%{user: user}) do
    project_credential = project_credential_fixture(user_id: user.id)
    %{project_credential: project_credential}
  end

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "Index" do
    setup [:create_credential, :create_project_credential]

    test "Side menu has credentials and user profile navigation", %{
      conn: conn
    } do
      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      assert index_live
             |> element("nav#side-menu a", "Credentials")
             |> has_element?()

      assert index_live
             |> element("nav#side-menu a", "User Profile")
             |> render_click()
             |> follow_redirect(conn, ~p"/profile")
    end

    test "lists all credentials", %{
      conn: conn,
      credential: credential
    } do
      {:ok, _index_live, html} = live(conn, ~p"/credentials")

      assert html =~ "Credentials"
      assert html =~ "Projects with Access"
      assert html =~ "Type"

      assert html =~
               credential.name |> Phoenix.HTML.Safe.to_iodata() |> to_string()

      [[], project_names] =
        Credentials.list_credentials_for_user(credential.user_id)
        |> Enum.sort_by(&(&1.project_credentials |> length))
        |> Enum.map(fn c ->
          Enum.map(c.projects, fn p -> p.name end)
        end)

      assert html =~ project_names |> Enum.join(", ")

      assert html =~ "Edit"
      assert html =~ "Production"
      assert html =~ credential.schema
      assert html =~ credential.name
    end

    # https://github.com/OpenFn/Lightning/issues/273 - allow users to delete

    test "can schedule for deletion a credential that is not associated to any activity",
         %{
           conn: conn,
           credential: credential
         } do
      {:ok, index_live, html} =
        live(conn, ~p"/credentials/#{credential.id}/delete")

      assert html =~ "Delete credential"

      assert html =~
               "Deleting this credential will immediately remove it from all jobs"

      refute html =~ "credential has been used in workflow attempts"

      assert index_live
             |> element("button", "Delete credential")
             |> has_element?()

      {:ok, view, html} =
        index_live
        |> element("button", "Delete credential")
        |> render_click()
        |> follow_redirect(conn, ~p"/credentials")

      assert html =~ "Credential scheduled for deletion"
      assert html =~ "Cancel deletion"
      assert html =~ "Delete now"

      assert has_element?(view, "#credential-#{credential.id}")
    end

    test "can schedule for deletion a credential that is associated to activities",
         %{
           conn: conn,
           credential: credential
         } do
      insert(:run, credential: credential)

      {:ok, index_live, html} =
        live(conn, ~p"/credentials/#{credential.id}/delete")

      assert html =~ "Delete credential"

      assert html =~ "Deleting this credential will immediately"
      assert html =~ "*This credential has been used in workflow attempts"

      assert index_live
             |> element("button", "Delete credential")
             |> has_element?()

      {:ok, view, html} =
        index_live
        |> element("button", "Delete credential")
        |> render_click()
        |> follow_redirect(conn, ~p"/credentials")

      assert html =~ "Credential scheduled for deletion"
      assert html =~ "Cancel deletion"
      assert html =~ "Delete now"

      assert has_element?(view, "#credential-#{credential.id}")
    end

    test "cancel a scheduled for deletion credential", %{
      conn: conn,
      credential: credential
    } do
      insert(:run, credential: credential)
      {:ok, credential} = Credentials.schedule_credential_deletion(credential)

      {:ok, index_live, _html} =
        live(conn, ~p"/credentials")

      assert index_live
             |> element("#credential-#{credential.id} a", "Cancel deletion")
             |> has_element?()

      index_live
      |> element("#credential-#{credential.id} a", "Cancel deletion")
      |> render_click()

      {:ok, index_live, html} = live(conn, ~p"/credentials")

      refute html =~ "Cancel deletion"
      refute html =~ "Delete now"

      assert html =~ "Delete"

      assert has_element?(index_live, "#credential-#{credential.id}")
    end

    test "can delete credential that has no activity in projects", %{
      conn: conn,
      credential: credential
    } do
      {:ok, credential} = Credentials.schedule_credential_deletion(credential)

      {:ok, index_live, html} =
        live(conn, ~p"/credentials/#{credential.id}/delete")

      assert html =~
               "Deleting this credential will immediately remove it from all jobs"

      refute html =~ "credential has been used in workflow attempts"

      assert index_live
             |> element("button", "Delete credential")
             |> has_element?()

      index_live |> element("button", "Delete credential") |> render_click()

      assert_redirected(index_live, ~p"/credentials")

      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      refute has_element?(index_live, "#credential-#{credential.id}")
    end

    test "cannot delete credential that has activity in projects", %{
      conn: conn,
      credential: credential
    } do
      insert(:run, credential: credential)
      {:ok, credential} = Credentials.schedule_credential_deletion(credential)

      {:ok, index_live, html} =
        live(conn, ~p"/credentials/#{credential.id}/delete")

      assert html =~ "This credential has been used in workflow attempts"
      assert html =~ "will be made unavailable for future use immediately"

      assert index_live |> element("button", "Ok, understood") |> has_element?()

      index_live |> element("button", "Ok, understood") |> render_click()

      assert_redirected(index_live, ~p"/credentials")

      {:ok, index_live, _html} =
        live(conn, ~p"/credentials")

      assert has_element?(index_live, "#credential-#{credential.id}")
    end

    test "user can only delete their own credential", %{
      conn: conn
    } do
      credential = credential_fixture()

      {:ok, _index_live, html} =
        live(conn, ~p"/credentials/#{credential.id}/delete")
        |> follow_redirect(conn, ~p"/credentials")

      assert html =~ "You can&#39;t perform this action"
    end
  end

  describe "Clicking new from the list view" do
    test "allows the user to define and save a new raw credential", %{
      conn: conn,
      project: project
    } do
      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      index_live |> select_credential_type("raw")
      index_live |> click_continue()

      assert index_live |> has_element?("#credential-form-new_body")

      index_live
      |> element("#project_list")
      |> render_change(%{"selected_project" => %{"id" => project.id}})

      index_live
      |> element("button", "Add")
      |> render_click()

      assert index_live
             |> form("#credential-form-new", credential: %{name: ""})
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _index_live, html} =
        index_live
        |> form("#credential-form-new", credential: @create_attrs)
        |> render_submit()
        |> follow_redirect(conn, ~p"/credentials")

      {path, flash} = assert_redirect(index_live)

      assert flash == %{"info" => "Credential created successfully"}
      assert path == "/credentials"

      assert html =~ project.name
      assert html =~ "some name"
    end

    test "allows the user to define and save a new dhis2 credential", %{
      conn: conn
    } do
      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      # Pick a type

      index_live |> select_credential_type("dhis2")
      index_live |> click_continue()

      refute index_live |> has_element?("#credential-type-picker")

      assert index_live |> fill_credential(%{body: %{username: ""}}) =~
               "can&#39;t be blank"

      assert index_live |> submit_disabled()

      assert index_live
             |> click_save() =~ "can&#39;t be blank"

      refute_redirected(index_live, ~p"/credentials")

      # Check that the fields are rendered in the same order as the JSON schema
      inputs_in_position =
        index_live
        |> element("#credential-form-new")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.attribute("input", "name")

      assert inputs_in_position == ~w(
               credential[name]
               credential[production]
               credential[production]
               credential[body][username]
               credential[body][password]
               credential[body][hostUrl]
               credential[body][apiVersion]
             )

      assert index_live
             |> fill_credential(%{
               name: "My Credential",
               body: %{username: "foo", password: "bar", hostUrl: "baz"}
             }) =~
               "expected to be a URI"

      assert index_live
             |> form("#credential-form-new",
               credential: %{body: %{hostUrl: "http://localhost"}}
             )
             |> render_change()

      refute index_live |> submit_disabled()

      {:ok, _index_live, _html} =
        index_live
        |> click_save()
        |> follow_redirect(conn, ~p"/credentials")

      {_path, flash} = assert_redirect(index_live)
      assert flash == %{"info" => "Credential created successfully"}
    end

    test "allows the user to define and save a new postgresql credential", %{
      conn: conn
    } do
      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      index_live |> select_credential_type("postgresql")
      index_live |> click_continue()

      refute index_live |> has_element?("#credential-type-picker")

      assert index_live |> fill_credential(%{body: %{user: ""}}) =~
               "can&#39;t be blank"

      assert index_live |> submit_disabled()

      assert index_live
             |> click_save() =~ "can&#39;t be blank"

      refute_redirected(index_live, ~p"/credentials")

      # Check that the fields are rendered in the same order as the JSON schema
      inputs_in_position =
        index_live
        |> element("#credential-form-new")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.attribute("input", "name")

      assert inputs_in_position == [
               "credential[name]",
               "credential[production]",
               "credential[production]",
               "credential[body][host]",
               "credential[body][port]",
               "credential[body][database]",
               "credential[body][user]",
               "credential[body][password]",
               "credential[body][ssl]",
               "credential[body][ssl]",
               "credential[body][allowSelfSignedCert]",
               "credential[body][allowSelfSignedCert]"
             ]

      body = %{
        user: "user1",
        password: "pass1",
        host: "not a URI",
        database: "test_db",
        port: "5000",
        ssl: "true",
        allowSelfSignedCert: "false"
      }

      credential_name = "Cast Postgres Credential"

      assert index_live
             |> fill_credential(%{
               name: credential_name,
               body: body
             }) =~
               "expected to be a URI"

      assert index_live
             |> form("#credential-form-new",
               credential: %{body: %{host: "http://localhost"}}
             )
             |> render_change()

      refute index_live |> submit_disabled()

      {:ok, _index_live, html} =
        index_live
        |> click_save()
        |> follow_redirect(conn, ~p"/credentials")

      assert %{
               body: %{
                 "port" => 5000,
                 "ssl" => true,
                 "allowSelfSignedCert" => false
               }
             } =
               Lightning.Repo.get_by(Lightning.Credentials.Credential,
                 name: credential_name
               )

      assert html =~ "Credential created successfully"
    end

    test "allows the user to define and save a new http credential", %{
      conn: conn
    } do
      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      index_live |> select_credential_type("http")
      index_live |> click_continue()

      assert index_live
             |> fill_credential(%{body: %{username: ""}}) =~ "can&#39;t be blank"

      assert index_live |> submit_disabled()

      assert index_live
             |> click_save() =~ "can&#39;t be blank"

      refute_redirected(index_live, ~p"/credentials")

      assert index_live
             |> fill_credential(%{
               name: "My Credential",
               body: %{username: "foo", password: "bar", baseUrl: "baz"}
             }) =~ "expected to be a URI"

      assert index_live
             |> fill_credential(%{
               body: %{baseUrl: "http://localhost"}
             })

      refute index_live |> submit_disabled()

      assert index_live
             |> fill_credential(%{body: %{baseUrl: ""}})

      refute index_live |> submit_disabled()

      {:ok, _index_live, _html} =
        index_live
        |> click_save()
        |> follow_redirect(
          conn,
          ~p"/credentials"
        )

      {_path, flash} = assert_redirect(index_live)
      assert flash == %{"info" => "Credential created successfully"}
    end
  end

  describe "Edit" do
    setup [:create_credential]

    test "updates a credential", %{conn: conn, credential: credential} do
      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      assert index_live
             |> fill_credential(
               @invalid_attrs,
               "#credential-form-#{credential.id}"
             ) =~
               "can&#39;t be blank"

      refute_redirected(index_live, ~p"/credentials")

      {:ok, _index_live, html} =
        index_live
        |> click_save(
          %{credential: @update_attrs},
          "#credential-form-#{credential.id}"
        )
        |> follow_redirect(conn, ~p"/credentials")

      {_path, flash} = assert_redirect(index_live)
      assert flash == %{"info" => "Credential updated successfully"}

      assert html =~ "some updated name"
    end

    test "adds new project with access", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project, project_users: [build(:project_user, user: user)])

      credential =
        insert(:credential,
          name: "my-credential",
          schema: "http",
          body: %{"username" => "test", "password" => "test"},
          user: user
        )

      audit_events_query =
        from(a in Lightning.Credentials.Audit.base_query(),
          where: a.item_id == ^credential.id,
          select: {a.event, type(a.changes, :map)}
        )

      assert Lightning.Repo.all(audit_events_query) == []

      {:ok, view, _html} = live(conn, ~p"/credentials/#{credential.id}")

      view
      |> element("#project_list")
      |> render_change(selected_project: %{"id" => project.id})

      view
      |> element("#add-new-project-button")
      |> render_click()

      view |> form("#credential-form") |> render_submit()

      assert_redirected(view, ~p"/credentials")

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

    test "removes project with access", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project, project_users: [build(:project_user, user: user)])

      credential =
        insert(:credential,
          name: "my-credential",
          schema: "http",
          body: %{"username" => "test", "password" => "test"},
          user: user
        )

      insert(:project_credential, project: project, credential: credential)

      audit_events_query =
        from(a in Lightning.Credentials.Audit.base_query(),
          where: a.item_id == ^credential.id,
          select: {a.event, type(a.changes, :map)}
        )

      assert Lightning.Repo.all(audit_events_query) == []

      {:ok, view, _html} = live(conn, ~p"/credentials/#{credential.id}")

      view
      |> element("#project_list")
      |> render_change(selected_project: %{"id" => project.id})

      view
      |> element("#delete-project-#{project.id}")
      |> render_click()

      view |> form("#credential-form") |> render_submit()

      assert_redirected(view, ~p"/credentials")

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

    test "users can only edit their own credentials", %{
      conn: conn
    } do
      # some credential for another user
      credential = CredentialsFixtures.credential_fixture()

      {:ok, _view, html} =
        live(conn, ~p"/credentials/#{credential.id}")
        |> follow_redirect(conn)
        |> follow_redirect(conn)

      assert html =~ "Sorry, we can&#39;t find anything here for you."
    end

    test "marks a credential for use in a 'production' system", %{
      conn: conn,
      credential: credential
    } do
      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      {:ok, _index_live, html} =
        index_live
        |> form("#credential-form-#{credential.id}",
          credential: Map.put(@update_attrs, :production, true)
        )
        |> render_submit()
        |> follow_redirect(
          conn,
          ~p"/credentials"
        )

      assert html =~ "some updated name"

      {_path, flash} = assert_redirect(index_live)
      assert flash == %{"info" => "Credential updated successfully"}
    end

    test "blocks credential transfer to invalid owner; allows to valid owner", %{
      conn: conn,
      user: first_owner,
      credential: credential_1
    } do
      user_2 = insert(:user)
      user_3 = insert(:user)

      project =
        insert(:project,
          name: "myproject",
          project_users: [%{user_id: first_owner.id}, %{user_id: user_2.id}]
        )

      credential =
        insert(:credential,
          user: first_owner,
          name: "the one for giving away",
          project_credentials: [
            %{project: project, credential: nil}
          ]
        )

      {:ok, index_live, html} = live(conn, ~p"/credentials")

      # both credentials appear in the list
      assert html =~ credential_1.name
      assert html =~ credential.name

      assert html =~ first_owner.id
      assert html =~ user_2.id
      assert html =~ user_3.id

      assert index_live
             |> form("#credential-form-#{credential.id}",
               credential: Map.put(@update_attrs, :user_id, user_3.id)
             )
             |> render_change() =~ "Invalid owner"

      #  Can't transfer to user who doesn't have access to right projects
      assert index_live |> submit_disabled()

      {:ok, _index_live, html} =
        index_live
        |> form("#credential-form-#{credential.id}",
          credential: %{
            body: "{\"a\":\"new_secret\"}",
            user_id: user_2.id
          }
        )
        |> render_submit()
        |> follow_redirect(
          conn,
          ~p"/credentials"
        )

      # Once the transfer is made, the credential should not show up in the list

      assert html =~ "Credential updated successfully"
      assert html =~ credential_1.name
      refute html =~ "the one for giving away"
    end
  end

  describe "googlesheets credential" do
    setup do
      bypass = Bypass.open()

      # TODO: replace this with a proper Mock via Lightning.Config
      Lightning.ApplicationHelpers.put_temporary_env(:lightning, :oauth_clients,
        google: [
          client_id: "foo",
          client_secret: "bar",
          wellknown_url: "http://localhost:#{bypass.port}/auth/.well-known"
        ]
      )

      {:ok, bypass: bypass}
    end

    test "allows the user to define and save a new google sheets credential", %{
      bypass: bypass,
      conn: conn,
      user: user
    } do
      expect_wellknown(bypass)

      expect_token(
        bypass,
        Lightning.AuthProviders.Google.get_wellknown!(),
        %{
          access_token: "ya29.a0AVvZ...",
          refresh_token: "1//03vpp6Li...",
          expires_in: 3600,
          token_type: "Bearer",
          id_token: "eyJhbGciO...",
          scope: "scope1 scope2"
        }
      )

      expect_userinfo(
        bypass,
        Lightning.AuthProviders.Google.get_wellknown!(),
        """
        {"picture": "image.png", "name": "Test User"}
        """
      )

      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      # Pick a type

      index_live |> select_credential_type("googlesheets")
      index_live |> click_continue()

      refute index_live |> has_element?("#credential-type-picker")

      index_live
      |> fill_credential(%{
        name: "My Google Sheets Credential"
      })

      # Get the state from the authorize url in order to fake the calling
      # off the action in the OidcController
      [subscription_id, mod, component_id] =
        index_live
        |> get_authorize_url()
        |> get_decoded_state()

      assert index_live.id == subscription_id
      assert index_live |> element(component_id)

      # Click on the 'Authorize with Google button
      index_live
      |> element("#google-sheets-inner-form #authorize-button")
      |> render_click()

      # Once authorizing the button isn't available
      refute index_live
             |> has_element?("#google-sheets-inner-form #authorize-button")

      # `handle_info/2` in LightingWeb.CredentialLive.Edit forwards the data
      # as a `send_update/3` call to the GoogleSheets component
      LightningWeb.OauthCredentialHelper.broadcast_forward(subscription_id, mod,
        id: component_id,
        code: "1234"
      )

      # Wait for the userinfo endpoint to be called
      assert wait_for_assigns(index_live, :userinfo),
             ":userinfo has not been set yet."

      # Rerender as the broadcast above has altered the LiveView state
      index_live |> render()

      assert index_live |> has_element?("span", "Test User")

      refute index_live |> submit_disabled()

      {:ok, _index_live, _html} =
        index_live
        |> form("#credential-form-new")
        |> render_submit()
        |> follow_redirect(
          conn,
          ~p"/credentials"
        )

      {_path, flash} = assert_redirect(index_live)
      assert flash == %{"info" => "Credential created successfully"}

      credential =
        Lightning.Credentials.list_credentials_for_user(user.id) |> List.first()

      token = Lightning.AuthProviders.Google.TokenBody.new(credential.body)
      expected_expiry = DateTime.to_unix(DateTime.utc_now()) + 3600

      assert %{
               access_token: "ya29.a0AVvZ...",
               refresh_token: "1//03vpp6Li...",
               expires_at: expiry,
               scope: "scope1 scope2"
             } = token

      assert (expiry - expected_expiry) in -1..1
    end

    test "correctly renders a valid existing token", %{
      conn: conn,
      user: user,
      bypass: bypass
    } do
      expect_wellknown(bypass)

      expect_userinfo(
        bypass,
        Lightning.AuthProviders.Google.get_wellknown!(),
        %{
          picture: "image.png",
          name: "Test User"
        }
      )

      expires_at = DateTime.to_unix(DateTime.utc_now()) + 3600

      credential_fixture(
        user_id: user.id,
        schema: "googlesheets",
        body: %{
          access_token: "ya29.a0AVvZ...",
          refresh_token: "1//03vpp6Li...",
          expires_at: expires_at,
          scope: "scope1 scope2"
        }
      )

      {:ok, edit_live, _html} = live(conn, ~p"/credentials")

      assert_receive {:phoenix, :send_update, _}

      # Wait for the userinfo endpoint to be called
      assert wait_for_assigns(edit_live, :userinfo),
             ":userinfo has not been set yet."

      edit_live |> render()

      assert edit_live |> has_element?("span", "Test User")
    end

    test "renders an error when a token has no refresh token", %{
      conn: conn,
      user: user,
      bypass: bypass
    } do
      expect_wellknown(bypass)

      expires_at = DateTime.to_unix(DateTime.utc_now()) + 3600

      credential_fixture(
        user_id: user.id,
        schema: "googlesheets",
        body: %{
          access_token: "ya29.a0AVvZ...",
          refresh_token: "",
          expires_at: expires_at,
          scope: "scope1 scope2"
        }
      )

      {:ok, edit_live, _html} = live(conn, ~p"/credentials")

      # Wait for next `send_update` triggered by the token Task calls
      assert_receive {:plug_conn, :sent}

      edit_live
      |> element("#google-sheets-inner-form")
      |> render()

      assert edit_live |> has_element?("p", "The token is missing it's")
    end

    test "renewing an expired but valid token", %{
      user: user,
      bypass: bypass,
      conn: conn
    } do
      expect_wellknown(bypass)

      expect_userinfo(
        bypass,
        Lightning.AuthProviders.Google.get_wellknown!(),
        """
        {"picture": "image.png", "name": "Test User"}
        """
      )

      expires_at = DateTime.to_unix(DateTime.utc_now()) - 50

      credential_fixture(
        user_id: user.id,
        schema: "googlesheets",
        body: %{
          access_token: "ya29.a0AVvZ...",
          refresh_token: "1//03vpp6Li...",
          expires_at: expires_at,
          scope: "scope1 scope2"
        }
      )

      expect_token(
        bypass,
        Lightning.AuthProviders.Google.get_wellknown!(),
        %{
          access_token: "ya29.a0AVvZ...",
          refresh_token: "1//03vpp6Li...",
          expires_in: 3600,
          token_type: "Bearer",
          id_token: "eyJhbGciO...",
          scope: "scope1 scope2"
        }
      )

      {:ok, edit_live, _html} = live(conn, ~p"/credentials")

      assert wait_for_assigns(edit_live, :userinfo),
             ":userinfo has not been set yet."

      edit_live |> render()

      assert edit_live |> has_element?("span", "Test User")
    end

    @tag :capture_log
    test "failing to retrieve userinfo", %{
      user: user,
      bypass: bypass,
      conn: conn
    } do
      expect_wellknown(bypass)

      expect_userinfo(
        bypass,
        Lightning.AuthProviders.Google.get_wellknown!(),
        {400,
         """
         {
           "error": "access_denied",
           "error_description": "You're not from around these parts are ya?"
         }
         """}
      )

      expires_at = DateTime.to_unix(DateTime.utc_now()) + 3600

      credential_fixture(
        user_id: user.id,
        schema: "googlesheets",
        body: %{
          access_token: "ya29.a0AVvZ...",
          refresh_token: "1//03vpp6Li...",
          expires_at: expires_at,
          scope: "scope1 scope2"
        }
      )

      {:ok, edit_live, _html} = live(conn, ~p"/credentials")

      assert wait_for_assigns(edit_live, :error)

      edit_live |> render()

      assert edit_live
             |> has_element?("p", "Failed retrieving your information.")

      # Now respond with success
      expect_userinfo(
        bypass,
        Lightning.AuthProviders.Google.get_wellknown!(),
        """
        {"picture": "image.png", "name": "Test User"}
        """
      )

      edit_live |> element("a", "try again.") |> render_click()

      assert wait_for_assigns(edit_live, :userinfo)

      assert edit_live |> has_element?("span", "Test User")
    end

    @tag :capture_log
    test "renewing an expired but invalid token", %{
      user: user,
      bypass: bypass,
      conn: conn
    } do
      expect_wellknown(bypass)

      expect_token(
        bypass,
        Lightning.AuthProviders.Google.get_wellknown!(),
        {400,
         """
         {
           "error": "access_denied",
           "error_description": "You're not from around these parts are ya?"
         }
         """}
      )

      expires_at = DateTime.to_unix(DateTime.utc_now()) - 50

      credential_fixture(
        user_id: user.id,
        schema: "googlesheets",
        body: %{
          access_token: "ya29.a0AVvZ...",
          refresh_token: "1//03vpp6Li...",
          expires_at: expires_at,
          scope: "scope1 scope2"
        }
      )

      {:ok, edit_live, _html} = live(conn, ~p"/credentials")

      assert wait_for_assigns(edit_live, :error)

      edit_live |> render()

      assert edit_live
             |> has_element?("p", "Failed renewing your access token.")
    end
  end

  describe "googlesheets credential (when client is not available)" do
    @tag :capture_log
    test "shows a warning that Google Sheets isn't available", %{conn: conn} do
      # TODO: replace this with a proper Mock via Lightning.Config
      Lightning.ApplicationHelpers.put_temporary_env(:lightning, :oauth_clients,
        google: []
      )

      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      index_live |> select_credential_type("googlesheets")
      index_live |> click_continue()

      refute index_live |> has_element?("#credential-type-picker")

      assert index_live
             |> has_element?("#google-sheets-inner-form", "No Client Configured")
    end
  end

  defp wait_for_assigns(live, key) do
    Enum.reduce_while(1..10, nil, fn n, _ ->
      {_mod, assigns} =
        Lightning.LiveViewHelpers.get_component_assigns_by(
          live,
          id: "google-sheets-inner-form"
        )

      if val = assigns[key] do
        {:halt, val}
      else
        Process.sleep(n * 10)
        {:cont, nil}
      end
    end)
  end

  defp get_authorize_url(live) do
    live
    |> element("#google-sheets-inner-form")
    |> render()
    |> Floki.parse_fragment!()
    |> Floki.find("a[phx-click=authorize_click]")
    |> Floki.attribute("href")
    |> List.first()
  end

  defp get_decoded_state(url) do
    %{query: query} = URI.parse(url)

    URI.decode_query(query)
    |> Map.get("state")
    |> LightningWeb.OauthCredentialHelper.decode_state()
  end

  defp submit_disabled(live) do
    live |> has_element?("button[type=submit][disabled]")
  end
end
