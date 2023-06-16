defmodule LightningWeb.CredentialLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest

  import Lightning.{
    JobsFixtures,
    CredentialsFixtures
  }

  alias Lightning.CredentialsFixtures
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
    credential = credential_fixture(user_id: user.id)
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

    test "deletes credential not used by a job", %{
      conn: conn,
      credential: credential
    } do
      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      assert index_live
             |> element("#credential-#{credential.id} a", "Delete")
             |> render_click() =~ "Credential deleted"

      refute has_element?(index_live, "#credential-#{credential.id}")
    end

    test "user can only delete their own credential", %{
      conn: conn
    } do
      credential = credential_fixture()

      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      assert index_live
             |> render_click("delete", %{"id" => credential.id}) =~
               "You can&#39;t perform this action"
    end
  end

  describe "Clicking new from the list view" do
    test "allows the user to define and save a new raw credential", %{
      conn: conn,
      project: project
    } do
      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      {:ok, new_live, _html} =
        index_live
        |> element("a", "New Credential")
        |> render_click()
        |> follow_redirect(conn, ~p"/credentials/new")

      new_live |> select_credential_type("raw")
      new_live |> click_continue()

      assert new_live |> has_element?("#credential-form_body")

      new_live
      |> element("#project_list")
      |> render_change(%{"selected_project" => %{"id" => project.id}})

      new_live
      |> element("button", "Add")
      |> render_click()

      assert new_live
             |> form("#credential-form", credential: %{name: ""})
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _index_live, html} =
        new_live
        |> form("#credential-form", credential: @create_attrs)
        |> render_submit()
        |> follow_redirect(conn, ~p"/credentials")

      {path, flash} = assert_redirect(new_live)

      assert flash == %{"info" => "Credential created successfully"}
      assert path == "/credentials"

      assert html =~ project.name
      assert html =~ "some name"
    end

    test "allows the user to define and save a new dhis2 credential", %{
      conn: conn
    } do
      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      {:ok, new_live, _html} =
        index_live
        |> element("a", "New Credential")
        |> render_click()
        |> follow_redirect(conn, ~p"/credentials/new")

      # Pick a type

      new_live |> select_credential_type("dhis2")
      new_live |> click_continue()

      refute new_live |> has_element?("#credential-type-picker")

      assert new_live |> fill_credential(%{body: %{username: ""}}) =~
               "can&#39;t be blank"

      assert new_live |> submit_disabled()

      assert new_live
             |> form("#credential-form")
             |> render_submit() =~ "can&#39;t be blank"

      refute_redirected(new_live, ~p"/credentials")

      # Check that the fields are rendered in the same order as the JSON schema
      inputs_in_position =
        new_live
        |> element("#credential-form")
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

      assert new_live
             |> form("#credential-form",
               credential: %{
                 name: "My Credential",
                 body: %{username: "foo", password: "bar", hostUrl: "baz"}
               }
             )
             |> render_change() =~ "expected to be a URI"

      assert new_live
             |> form("#credential-form",
               credential: %{body: %{hostUrl: "http://localhost"}}
             )
             |> render_change()

      refute new_live |> submit_disabled()

      {:ok, _index_live, _html} =
        new_live
        |> form("#credential-form")
        |> render_submit()
        |> follow_redirect(conn, ~p"/credentials")

      {_path, flash} = assert_redirect(new_live)
      assert flash == %{"info" => "Credential created successfully"}
    end

    test "allows the user to define and save a new http credential", %{
      conn: conn
    } do
      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      {:ok, new_live, _html} =
        index_live
        |> element("a", "New Credential")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.credential_edit_path(conn, :new)
        )

      new_live |> select_credential_type("http")
      new_live |> click_continue()

      assert new_live
             |> fill_credential(%{body: %{username: ""}}) =~ "can&#39;t be blank"

      assert new_live |> submit_disabled()

      assert new_live
             |> form("#credential-form")
             |> render_submit() =~ "can&#39;t be blank"

      refute_redirected(new_live, ~p"/credentials")

      assert new_live
             |> fill_credential(%{
               name: "My Credential",
               body: %{username: "foo", password: "bar", baseUrl: "baz"}
             }) =~ "expected to be a URI"

      assert new_live |> fill_credential(%{body: %{baseUrl: "http://localhost"}})

      refute new_live |> submit_disabled()

      assert new_live |> fill_credential(%{body: %{baseUrl: ""}})

      refute new_live |> submit_disabled()

      {:ok, _index_live, _html} =
        new_live
        |> form("#credential-form")
        |> render_submit()
        |> follow_redirect(
          conn,
          ~p"/credentials"
        )

      {_path, flash} = assert_redirect(new_live)
      assert flash == %{"info" => "Credential created successfully"}
    end
  end

  describe "Edit" do
    setup [:create_credential]

    test "updates a credential", %{conn: conn, credential: credential} do
      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      {:ok, form_live, _} =
        index_live
        |> element("#credential-#{credential.id} a", "Edit")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.credential_edit_path(conn, :edit, credential)
        )

      assert form_live |> fill_credential(@invalid_attrs) =~ "can&#39;t be blank"

      refute_redirected(form_live, ~p"/credentials")

      {:ok, _index_live, html} =
        form_live
        |> form("#credential-form", credential: @update_attrs)
        |> render_submit()
        |> follow_redirect(
          conn,
          ~p"/credentials"
        )

      {_path, flash} = assert_redirect(form_live)
      assert flash == %{"info" => "Credential updated successfully"}

      assert html =~ "some updated name"
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

      {:ok, form_live, _} =
        index_live
        |> element("#credential-#{credential.id} a", "Edit")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.credential_edit_path(conn, :edit, credential)
        )

      {:ok, _index_live, html} =
        form_live
        |> form("#credential-form",
          credential: Map.put(@update_attrs, :production, true)
        )
        |> render_submit()
        |> follow_redirect(
          conn,
          ~p"/credentials"
        )

      assert html =~ "some updated name"

      {_path, flash} = assert_redirect(form_live)
      assert flash == %{"info" => "Credential updated successfully"}
    end

    test "blocks credential transfer to invalid owner; allows to valid owner", %{
      conn: conn,
      user: first_owner
    } do
      user_2 = Lightning.AccountsFixtures.user_fixture()
      user_3 = Lightning.AccountsFixtures.user_fixture()

      {:ok, %Lightning.Projects.Project{id: project_id}} =
        Lightning.Projects.create_project(%{
          name: "some-name",
          project_users: [%{user_id: first_owner.id}, %{user_id: user_2.id}]
        })

      credential =
        credential_fixture(
          user_id: first_owner.id,
          name: "the one for giving away",
          project_credentials: [
            %{project_id: project_id}
          ]
        )

      {:ok, index_live, html} = live(conn, ~p"/credentials")

      # both credentials appear in the list
      assert html =~ "some name"
      assert html =~ "the one for giving away"

      {:ok, form_live, html} =
        index_live
        |> element("#credential-#{credential.id} a", "Edit")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.credential_edit_path(conn, :edit, credential)
        )

      assert html =~ first_owner.id
      assert html =~ user_2.id
      assert html =~ user_3.id

      assert form_live
             |> form("#credential-form",
               credential: Map.put(@update_attrs, :user_id, user_3.id)
             )
             |> render_change() =~ "Invalid owner"

      #  Can't transfer to user who doesn't have access to right projects
      assert form_live |> submit_disabled()

      {:ok, _index_live, html} =
        form_live
        |> form("#credential-form",
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

      {_path, flash} = assert_redirect(form_live)
      assert flash == %{"info" => "Credential updated successfully"}

      # Once the transfer is made, the credential should not show up in the list
      assert html =~ "some name"
      refute html =~ "the one for giving away"
    end
  end

  describe "New credential from project context " do
    setup %{project: project} do
      %{job: job} = workflow_job_fixture(project_id: project.id)
      %{job: job}
    end

    test "open credential modal from the job inspector (edit_job)", %{
      conn: conn,
      project: project,
      job: job
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{job.workflow_id}/j/#{job.id}")

      assert has_element?(view, "#builder-#{job.id}")

      # open the new credential modal

      assert view
             |> element("#new-credential-launcher", "New credential")
             |> render_click()

      # assertions

      assert has_element?(view, "#credential-type-picker")
      view |> select_credential_type("http")
      view |> click_continue()

      refute has_element?(view, "#project_list")
    end

    test "create new credential from job inspector and update the job form", %{
      conn: conn,
      project: project,
      job: job
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{job.workflow_id}/j/#{job.id}")

      # open the new credential modal

      assert view
             |> element("#new-credential-launcher", "New credential")
             |> render_click()

      # fill the modal and save
      view |> select_credential_type("raw")
      view |> click_continue()

      view
      |> form("#credential-form",
        credential: %{
          name: "newly created credential",
          body: Jason.encode!(%{"a" => 1})
        }
      )
      |> render_submit()

      # assertions

      refute has_element?(view, "#credential-form")

      assert view
             |> element(
               ~S{#job-form select#credentialField option[selected=selected]}
             )
             |> render() =~ "newly created credential",
             "Should have the project credential selected"
    end

    test "create new credential from edit job form and update the job form", %{
      conn: conn,
      project: project,
      job: job
    } do
      {:ok, view, _html} =
        live(conn, ~p"/projects/#{project.id}/w/#{job.workflow_id}/j/#{job.id}")

      # change the job name so we can assert that the form state had been
      # kept after saving the new credential
      view
      |> form("#job-form", job_form: %{name: "last typed name"})
      |> render_change()

      # open the new credential modal
      assert view
             |> element("#new-credential-launcher", "New credential")
             |> render_click()

      # fill the modal and save

      view |> select_credential_type("raw")
      view |> click_continue()

      view
      |> form("#credential-form",
        credential: %{
          name: "newly created credential",
          body: Jason.encode!(%{"a" => 1})
        }
      )
      |> render_submit()

      # assertions

      refute has_element?(view, "#credential-form")

      assert view
             |> element(
               ~S{#job-form select#credentialField option[selected=selected]}
             )
             |> render() =~ "newly created credential",
             "Should have the project credential selected"

      assert view
             |> element(~S{#job-form input#job-form_name})
             |> render() =~ "last typed name",
             "Should have kept the job form state after saving the new credential"
    end
  end

  describe "googlesheets credential" do
    setup do
      bypass = Bypass.open()

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
      Lightning.BypassHelpers.expect_wellknown(bypass)

      Lightning.BypassHelpers.expect_token(
        bypass,
        Lightning.AuthProviders.Google.get_wellknown!(),
        """
        {
          "access_token": "ya29.a0AVvZ...",
          "refresh_token": "1//03vpp6Li...",
          "expires_in": 3600,
          "token_type": "Bearer",
          "id_token": "eyJhbGciO...",
          "scope": "scope1 scope2"
        }
        """
      )

      Lightning.BypassHelpers.expect_userinfo(
        bypass,
        Lightning.AuthProviders.Google.get_wellknown!(),
        """
        {"picture": "image.png", "name": "Test User"}
        """
      )

      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      {:ok, new_live, _html} =
        index_live
        |> element("a", "New Credential")
        |> render_click()
        |> follow_redirect(
          conn,
          ~p"/credentials/new"
        )

      # Pick a type

      new_live |> select_credential_type("googlesheets")
      new_live |> click_continue()

      refute new_live |> has_element?("#credential-type-picker")

      new_live |> fill_credential(%{name: "My Google Sheets Credential"})

      assert new_live |> submit_disabled(),
             "Submit should be disabled since the `body` hasn't been populated correctly"

      # Get the state from the authorize url in order to fake the calling
      # off the action in the OidcController
      [subscription_id, mod, component_id] =
        new_live
        |> get_authorize_url()
        |> get_decoded_state()

      assert new_live.id == subscription_id
      assert new_live |> element(component_id)

      # Click on the 'Authorize with Google button
      new_live
      |> element("#google-sheets-inner-form #authorize-button")
      |> render_click()

      # Once authorizing the button isn't available
      refute new_live
             |> has_element?("#google-sheets-inner-form #authorize-button")

      # `handle_info/2` in LightingWeb.CredentialLive.Edit forwards the data
      # as a `send_update/3` call to the GoogleSheets component
      LightningWeb.OauthCredentialHelper.broadcast_forward(subscription_id, mod,
        id: component_id,
        code: "1234"
      )

      # Wait for the userinfo endpoint to be called
      assert wait_for_assigns(new_live, :userinfo),
             ":userinfo has not been set yet."

      # Rerender as the broadcast above has altered the LiveView state
      new_live |> render()

      assert new_live |> has_element?("span", "Test User")

      refute new_live |> submit_disabled()

      {:ok, _index_live, _html} =
        new_live
        |> form("#credential-form")
        |> render_submit()
        |> follow_redirect(
          conn,
          ~p"/credentials"
        )

      {_path, flash} = assert_redirect(new_live)
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
      Lightning.BypassHelpers.expect_wellknown(bypass)

      Lightning.BypassHelpers.expect_userinfo(
        bypass,
        Lightning.AuthProviders.Google.get_wellknown!(),
        """
        {"picture": "image.png", "name": "Test User"}
        """
      )

      expires_at = DateTime.to_unix(DateTime.utc_now()) + 3600

      credential =
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

      {:ok, edit_live, _html} = live(conn, ~p"/credentials/#{credential.id}")

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
      Lightning.BypassHelpers.expect_wellknown(bypass)

      expires_at = DateTime.to_unix(DateTime.utc_now()) + 3600

      credential =
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

      {:ok, edit_live, _html} = live(conn, ~p"/credentials/#{credential.id}")

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
      Lightning.BypassHelpers.expect_wellknown(bypass)

      Lightning.BypassHelpers.expect_userinfo(
        bypass,
        Lightning.AuthProviders.Google.get_wellknown!(),
        """
        {"picture": "image.png", "name": "Test User"}
        """
      )

      expires_at = DateTime.to_unix(DateTime.utc_now()) - 50

      credential =
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

      Lightning.BypassHelpers.expect_token(
        bypass,
        Lightning.AuthProviders.Google.get_wellknown!(),
        """
        {
          "access_token": "ya29.a0AVvZ...",
          "refresh_token": "1//03vpp6Li...",
          "expires_in": 3600,
          "token_type": "Bearer",
          "id_token": "eyJhbGciO...",
          "scope": "scope1 scope2"
        }
        """
      )

      {:ok, edit_live, _html} = live(conn, ~p"/credentials/#{credential.id}")

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
      Lightning.BypassHelpers.expect_wellknown(bypass)

      Lightning.BypassHelpers.expect_userinfo(
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

      credential =
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

      {:ok, edit_live, _html} = live(conn, ~p"/credentials/#{credential.id}")

      assert wait_for_assigns(edit_live, :error)

      edit_live |> render()

      assert edit_live
             |> has_element?("p", "Failed retrieving your information.")

      # Now respond with success
      Lightning.BypassHelpers.expect_userinfo(
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
      Lightning.BypassHelpers.expect_wellknown(bypass)

      Lightning.BypassHelpers.expect_token(
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

      credential =
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

      {:ok, edit_live, _html} = live(conn, ~p"/credentials/#{credential.id}")

      assert wait_for_assigns(edit_live, :error)

      edit_live |> render()

      assert edit_live
             |> has_element?("p", "Failed renewing your access token.")
    end
  end

  describe "googlesheets credential (when client is not available)" do
    @tag :capture_log
    test "shows a warning that Google Sheets isn't available", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      {:ok, new_live, _html} =
        index_live
        |> element("a", "New Credential")
        |> render_click()
        |> follow_redirect(conn, ~p"/credentials/new")

      new_live |> select_credential_type("googlesheets")
      new_live |> click_continue()

      refute new_live |> has_element?("#credential-type-picker")

      assert new_live
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
    live |> has_element?("button[disabled][type=submit]")
  end

  defp select_credential_type(live, type) do
    live
    |> form("#credential-type-picker", type: %{selected: type})
    |> render_change()
  end

  defp click_continue(live) do
    live
    |> element("button", "Continue")
    |> render_click()
  end

  defp fill_credential(live, params) when is_map(params) do
    live
    |> form("#credential-form", credential: params)
    |> render_change()
  end
end
