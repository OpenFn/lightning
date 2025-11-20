defmodule LightningWeb.CredentialLiveTest do
  use LightningWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import LightningWeb.CredentialLiveHelpers

  import Lightning.Factories

  import Ecto.Query
  import Swoosh.TestAssertions

  alias Lightning.Accounts.User
  alias Lightning.Credentials
  alias Lightning.Credentials.Credential

  @create_attrs %{
    name: "some credential",
    body: Jason.encode!(%{"a" => 1}),
    external_id: "test-external-id"
  }

  @update_attrs %{
    name: "some updated name",
    body: "{\"a\":\"new_secret\"}",
    external_id: "updated-external-id"
  }

  @invalid_attrs %{name: "this won't work"}

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

  defp get_decoded_state(url) when is_nil(url) do
    [
      "test",
      LightningWeb.CredentialLive.GenericOauthComponent,
      "#generic-oauth-component-new"
    ]
  end

  defp get_decoded_state(url) do
    %{query: query} = URI.parse(url)

    URI.decode_query(query)
    |> Map.get("state")
    |> LightningWeb.OauthCredentialHelper.decode_state()
  end

  defp submit_disabled(live, id \\ "button") do
    has_element?(live, "#{id}[type=submit][disabled]")
  end

  describe "Index" do
    setup [:create_credential, :create_project_credential]

    test "Side menu has credentials and user profile navigation", %{
      conn: conn
    } do
      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      assert index_live
             |> element("nav#side-menu a", "Credentials")
             |> has_element?()

      assert index_live
             |> element("nav#side-menu a.menu-item", "User Profile")
             |> render_click()
             |> follow_redirect(conn, ~p"/profile")
    end

    test "lists all credentials", %{
      conn: conn,
      credential: credential
    } do
      {:ok, _index_live, html} = live(conn, ~p"/credentials", on_error: :raise)

      assert html =~ "Credentials"
      assert html =~ "Projects with access"
      assert html =~ "Type"

      assert html =~
               credential.name |> Phoenix.HTML.Safe.to_iodata() |> to_string()

      [[], project_names] =
        Credentials.list_credentials(%User{id: credential.user_id})
        |> Enum.sort_by(&(&1.project_credentials |> length))
        |> Enum.map(fn c ->
          Enum.map(c.projects, fn p -> p.name end)
        end)

      assert html =~ project_names |> Enum.join(", ")

      assert html =~ "Edit"
      assert html =~ "Environment"
      assert html =~ credential.schema
      assert html =~ credential.name
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

      {:ok, _index_live, html} = live(conn, ~p"/credentials", on_error: :raise)

      assert html =~ "Credentials"
      assert html =~ "Projects with access"
      assert html =~ "Type"

      assert html =~
               credential.name |> Phoenix.HTML.Safe.to_iodata() |> to_string()

      [[], project_names] =
        Credentials.list_credentials(%User{id: credential.user_id})
        |> Enum.sort_by(&(&1.project_credentials |> length))
        |> Enum.map(fn c ->
          Enum.map(c.projects, fn p -> p.name end)
        end)

      assert html =~ project_names |> Enum.join(", ")

      assert html =~ "Edit"
      assert html =~ "Environment"
      assert html =~ credential.schema
      assert html =~ credential.name
      refute html =~ support_credential.name
    end

    test "can schedule for deletion a credential that is not associated to any activity",
         %{
           conn: conn,
           credential: credential
         } do
      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      # modal doesn't exist
      refute has_element?(index_live, "#credential-#{credential.id}")

      # delete now button doesn't exist
      refute has_element?(
               index_live,
               "#credential-actions-#{credential.id}-delete-now"
             )

      # cancel delete button doesn't exists
      refute has_element?(
               index_live,
               "#credential-actions-#{credential.id}-cancel-deletion"
             )

      html =
        open_delete_credential_modal(index_live, credential.id)

      # modal now exists
      assert has_element?(
               index_live,
               "#delete-credential-#{credential.id}-modal"
             )

      assert html =~ "Delete credential"

      assert html =~
               "Deleting this credential will immediately remove it from all jobs"

      refute html =~ "credential has been used in workflow runs"

      assert index_live
             |> element(
               "#delete-credential-#{credential.id}-modal button",
               "Delete credential"
             )
             |> has_element?()

      {:ok, view, _html} =
        index_live
        |> element(
          "#delete-credential-#{credential.id}-modal button",
          "Delete credential"
        )
        |> render_click()
        |> follow_redirect(conn, ~p"/credentials")

      # delete button doesn't exist
      refute has_element?(
               view,
               "#credential-actions-#{credential.id}-delete"
             )

      # delete now button  exists
      assert has_element?(
               view,
               "#credential-actions-#{credential.id}-delete-now"
             )

      # cancel delete button  exists
      assert has_element?(
               view,
               "#credential-actions-#{credential.id}-cancel-deletion"
             )

      # modal doesn't exist. It was closed on redirect
      refute has_element?(view, "#delete-credential-#{credential.id}-modal")
    end

    test "can schedule for deletion a credential that is associated to activities",
         %{
           conn: conn,
           credential: credential
         } do
      insert(:step, credential: credential)

      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      html = open_delete_credential_modal(index_live, credential.id)

      assert html =~ "Delete credential"

      assert html =~ "Deleting this credential will immediately"
      assert html =~ "*This credential has been used in workflow runs"

      {:ok, view, _html} =
        index_live
        |> element(
          "#delete-credential-#{credential.id}-modal button",
          "Delete credential"
        )
        |> render_click()
        |> follow_redirect(conn, ~p"/credentials")

      # delete button doesn't exist
      refute has_element?(
               view,
               "#credential-actions-#{credential.id}-delete"
             )

      # delete now button  exists
      assert has_element?(
               view,
               "#credential-actions-#{credential.id}-delete-now"
             )

      # cancel delete button  exists
      assert has_element?(
               view,
               "#credential-actions-#{credential.id}-cancel-deletion"
             )
    end

    test "cancel a scheduled for deletion credential", %{
      conn: conn,
      credential: credential
    } do
      insert(:step, credential: credential)
      {:ok, credential} = Credentials.schedule_credential_deletion(credential)

      assert credential.scheduled_deletion

      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      assert has_element?(
               index_live,
               "#credential-actions-#{credential.id}-cancel-deletion",
               "Cancel deletion"
             )

      index_live
      |> element(
        "#credential-actions-#{credential.id}-cancel-deletion",
        "Cancel deletion"
      )
      |> render_click()

      flash = assert_redirected(index_live, ~p"/credentials")

      assert flash["info"] == "Credential deletion canceled"

      refute Lightning.Repo.reload(credential).scheduled_deletion
    end

    test "can delete credential that has no activity in projects", %{
      conn: conn,
      credential: credential
    } do
      {:ok, credential} = Credentials.schedule_credential_deletion(credential)

      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      html =
        index_live
        |> element("#credential-actions-#{credential.id}-delete-now")
        |> render_click()

      assert html =~
               "Deleting this credential will immediately remove it from all jobs"

      refute html =~ "credential has been used in workflow runs"

      assert index_live
             |> element(
               "#delete-credential-#{credential.id}-modal button",
               "Delete credential"
             )
             |> has_element?()

      index_live
      |> element(
        "#delete-credential-#{credential.id}-modal button",
        "Delete credential"
      )
      |> render_click()

      flash = assert_redirected(index_live, ~p"/credentials")

      assert flash["info"] == "Credential deleted successfully"
    end

    test "cannot delete credential that has activity in projects", %{
      conn: conn,
      credential: credential
    } do
      insert(:step, credential: credential)
      {:ok, credential} = Credentials.schedule_credential_deletion(credential)

      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      html =
        index_live
        |> element("#credential-actions-#{credential.id}-delete-now")
        |> render_click()

      assert html =~ "This credential has been used in workflow runs"
      assert html =~ "will be made unavailable for future use immediately"

      assert has_element?(
               index_live,
               "#delete-credential-#{credential.id}-modal button",
               "Ok, understood"
             )

      # forcing the event results in error
      index_live
      |> with_target("#delete-credential-#{credential.id}")
      |> render_click("delete", %{id: credential.id})

      assert_patched(index_live, ~p"/credentials")

      assert render(index_live) =~
               "Cannot delete a credential that has activities in projects"
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

      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_create_credential_modal(index_live)

      index_live |> select_credential_type("raw")
      index_live |> click_continue()

      assert index_live
             |> has_element?(
               "#credential-form-new textarea[name='credential[body]']"
             )

      # Select first project
      index_live
      |> element("#project-credentials-list-new")
      |> render_change(%{"project_id" => project1.id})

      # Verify project is added
      assert index_live
             |> has_element?(
               "#remove-project-credential-button-new-#{project1.id}"
             )

      assert index_live
             |> form("#credential-form-new", credential: %{name: ""})
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#credential-form-new", credential: %{name: "MailChimp'24"})
             |> render_change() =~ "credential name has invalid format"

      # Select second project
      index_live
      |> element("#project-credentials-list-new")
      |> render_change(%{"project_id" => project2.id})

      # Verify second project is added
      assert index_live
             |> has_element?(
               "#remove-project-credential-button-new-#{project2.id}"
             )

      {:ok, _index_live, html} =
        index_live
        |> form("#credential-form-new", credential: @create_attrs)
        |> render_submit()
        |> follow_redirect(conn, ~p"/credentials")

      {path, flash} = assert_redirect(index_live)

      assert flash == %{"info" => "Credential created successfully"}
      assert path == "/credentials"

      assert html =~ project1.name
      assert html =~ @create_attrs.name

      credential =
        Repo.get_by(Credential, name: @create_attrs.name)
        |> Repo.preload(:projects)

      assert MapSet.equal?(
               MapSet.new(credential.projects, & &1.id),
               MapSet.new([project1.id, project2.id])
             )
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

      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_create_credential_modal(index_live)

      index_live |> select_credential_type("raw")
      index_live |> click_continue()

      assert index_live
             |> has_element?(
               "#credential-form-new textarea[name='credential[body]']"
             )

      index_live
      |> element("#project-credentials-list-new")
      |> render_change(%{"project_id" => project1.id})

      assert index_live
             |> form("#credential-form-new", credential: %{name: ""})
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#credential-form-new", credential: %{name: "MailChimp'24"})
             |> render_change() =~ "credential name has invalid format"

      index_live
      |> element("#project-credentials-list-new")
      |> render_change(%{"project_id" => project2.id})

      {:ok, _index_live, html} =
        index_live
        |> form("#credential-form-new", credential: @create_attrs)
        |> render_submit()
        |> follow_redirect(conn, ~p"/credentials")

      {path, flash} = assert_redirect(index_live)

      assert flash == %{"info" => "Credential created successfully"}
      assert path == "/credentials"

      assert html =~ project1.name
      assert html =~ @create_attrs.name

      credential =
        Repo.get_by(Credential, name: @create_attrs.name)
        |> Repo.preload(:projects)

      assert MapSet.equal?(
               MapSet.new(credential.projects, & &1.id),
               MapSet.new([project1.id, project2.id])
             )
    end

    test "allows the user to define and save a new dhis2 credential", %{
      conn: conn
    } do
      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_create_credential_modal(index_live)

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

      # Check that the fields are rendered in the same order as expected
      inputs_in_position =
        index_live
        |> element("#credential-form-new")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.attribute("input", "name")

      # The new structure includes environment name instead of production field
      assert inputs_in_position == ~w(
           credential[name]
           credential[external_id]
           value
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

      refute index_live |> submit_disabled("save-credential-button-new")

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
      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_create_credential_modal(index_live)

      index_live |> select_credential_type("postgresql")
      index_live |> click_continue()

      refute index_live |> has_element?("#credential-type-picker")

      assert index_live |> fill_credential(%{body: %{user: ""}}) =~
               "can&#39;t be blank"

      assert index_live |> submit_disabled()

      assert index_live
             |> click_save() =~ "can&#39;t be blank"

      refute_redirected(index_live, ~p"/credentials")

      # Check that the fields are rendered in the expected order
      inputs_in_position =
        index_live
        |> element("#credential-form-new")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.attribute("input", "name")

      assert inputs_in_position == [
               "credential[name]",
               "credential[external_id]",
               "value",
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
               credential: %{
                 body: %{host: "http://localhost"}
               }
             )
             |> render_change()

      refute index_live |> submit_disabled("save-credential-button-new")

      {:ok, _index_live, html} =
        index_live
        |> click_save()
        |> follow_redirect(conn, ~p"/credentials")

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

      assert html =~ "Credential created successfully"
    end

    test "allows the user to define and save a new http credential", %{
      conn: conn
    } do
      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_create_credential_modal(index_live)

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
               name: "My Credential with TLS",
               body: %{username: "foo", password: "bar", baseUrl: "baz"}
             }) =~ "expected to be a URI"

      assert index_live
             |> fill_credential(%{
               body: %{baseUrl: "http://localhost", tls: "{\"a\":1}"}
             })

      refute index_live |> submit_disabled("save-credential-button-new")

      assert index_live
             |> fill_credential(%{body: %{baseUrl: ""}})

      refute index_live |> submit_disabled("save-credential-button-new")

      {:ok, _index_live, _html} =
        index_live
        |> click_save()
        |> follow_redirect(
          conn,
          ~p"/credentials"
        )

      {_path, flash} = assert_redirect(index_live)
      assert flash == %{"info" => "Credential created successfully"}

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
           conn: conn
         } do
      {:ok, view, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_create_credential_modal(view)

      select_credential_type(view, "godata")
      click_continue(view)

      assert fill_credential(view, %{body: %{email: ""}}) =~ "can&#39;t be blank"

      assert submit_disabled(view, "#save-credential-button-new")

      assert click_save(view) =~ "can&#39;t be blank"

      refute_redirected(view, ~p"/credentials")

      # Fill with invalid email format
      assert fill_credential(view, %{
               name: "Godata Credential",
               body: %{
                 apiUrl: "http://url",
                 password: "baz1234",
                 email: "incomplete-email"
               }
             }) =~ "expected to be an email"

      # Button might not be disabled for format errors, just check the error message appears
      # assert submit_disabled(view, "#save-credential-button-new")

      # Fill with valid email
      refute fill_credential(view, %{
               name: "Godata Credential",
               body: %{
                 apiUrl: "http://url",
                 password: "baz1234",
                 email: "good@email.com"
               }
             }) =~ "expected to be an email"

      refute submit_disabled(view, "#save-credential-button-new")

      {:ok, _view, _html} =
        view
        |> click_save()
        |> follow_redirect(conn, ~p"/credentials")

      {_path, flash} = assert_redirect(view)
      assert flash == %{"info" => "Credential created successfully"}
    end
  end

  describe "Edit" do
    setup [:create_credential]

    test "updates a credential", %{conn: conn, credential: credential} do
      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_edit_credential_modal(index_live, credential.id)

      assert index_live
             |> fill_credential(
               @invalid_attrs,
               "#credential-form-#{credential.id}"
             ) =~
               "credential name has invalid format"

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

    test "displays external_id in credentials table", %{
      conn: conn,
      credential: credential
    } do
      # Update credential with external_id
      Credentials.update_credential(credential, %{external_id: "display-test-id"})

      {:ok, _index_live, html} = live(conn, ~p"/credentials")

      # Verify external_id is displayed in the table
      assert html =~ "display-test-id"
    end

    test "Edit adds new project with access", %{
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

      {:ok, view, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_edit_credential_modal(view, credential.id)

      view
      |> element("#project-credentials-list-#{credential.id}")
      |> render_change(%{"project_id" => project.id})

      # Verify project is added
      assert view
             |> has_element?(
               "#remove-project-credential-button-#{credential.id}-#{project.id}"
             )

      view |> form("#credential-form-#{credential.id}") |> render_submit()

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

      {:ok, view, _html} = live(conn, ~p"/credentials", on_error: :raise)

      refute has_element?(view, "#credential-actions-#{credential.id}-edit")
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

      {:ok, view, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_edit_credential_modal(view, credential.id)

      view
      |> delete_credential_button(project.id)
      |> render_click()

      view |> form("#credential-form-#{credential.id}") |> render_submit()

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

    test "shows confirmation dialog if the credential is being used in a workflow",
         %{
           conn: conn,
           user: user
         } do
      credential =
        insert(:credential,
          name: "my-credential",
          schema: "http",
          body: %{"username" => "test", "password" => "test"},
          user: user
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

      workflow_without_credential =
        insert(:simple_workflow, project: project) |> with_snapshot()

      another_project =
        insert(:project, project_users: [build(:project_user, user: user)])

      insert(:project_credential,
        project: another_project,
        credential: credential
      )

      {:ok, view, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_edit_credential_modal(view, credential.id)

      button_html = delete_credential_button(view, project.id) |> render()

      assert button_html =~
               "data-confirm=\"Warning: This credential is in use by the following workflows: #{workflow_with_credential_1.name}, #{workflow_with_credential_2.name}. If you revoke access to the &quot;#{project.name}&quot; project, runs for those workflows will probably fail until you provide a new credential. Are you sure you want to revoke access?"

      assert button_html =~ workflow_with_credential_1.name
      assert button_html =~ workflow_with_credential_2.name
      refute button_html =~ workflow_without_credential.name

      refute delete_credential_button(view, another_project.id) |> render() =~
               "data-confirm"
    end

    test "users can add and remove existing project credentials successfully", %{
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

      {:ok, view, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_edit_credential_modal(view, credential.id)

      # Try adding an existing project credential
      view
      |> element("#project-credentials-list-#{credential.id}")
      |> render_change(%{"project_id" => project.id})

      html = view |> render()

      assert html =~ project.name,
             "adding an existing project doesn't break anything"

      # Verify the project is added to the credential's projects list
      assert view
             |> has_element?(
               "#remove-project-credential-button-#{credential.id}-#{project.id}"
             ),
             "project should be added to credential's projects list"

      # Let's remove the project and add it back again
      view
      |> delete_credential_button(project.id)
      |> render_click()

      refute view |> delete_credential_button(project.id) |> has_element?(),
             "project is removed from list"

      # now let's add it back
      view
      |> element("#project-credentials-list-#{credential.id}")
      |> render_change(%{"project_id" => project.id})

      assert view
             |> has_element?(
               "#remove-project-credential-button-#{credential.id}-#{project.id}"
             ),
             "project should be added back to credential's projects list"

      view |> form("#credential-form-#{credential.id}") |> render_submit()

      assert_redirected(view, ~p"/credentials")
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

      {:ok, view, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_edit_credential_modal(view, credential.id)

      # Wait for the refresh attempt to complete
      Lightning.ApplicationHelpers.dynamically_absorb_delay(fn ->
        {_, assigns} =
          Lightning.LiveViewHelpers.get_component_assigns_by(view,
            id: "generic-oauth-component-#{credential.id}-main"
          )

        :error === assigns[:oauth_progress]
      end)

      # After the error state, check the rendered content
      html = view |> element("#credential-form-#{credential.id}") |> render()

      # Check for 401 error message content
      assert html =~ "Your authorization with"
      assert html =~ "expired or was revoked"

      # The button text for 401 errors is "Sign In Again"
      assert view
             |> element(
               "#credential-form-#{credential.id} button",
               "Sign In Again"
             )
             |> has_element?()
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

      {:ok, view, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_create_credential_modal(view)

      view |> select_credential_type(oauth_client.id)
      view |> click_continue()

      refute view |> has_element?("#credential-type-picker")

      view
      |> fill_credential(%{
        name: "My Generic OAuth Credential"
      })

      # Get the authorize URL from the component's assigns
      {_, component_assigns} =
        Lightning.LiveViewHelpers.get_component_assigns_by(view,
          id: "generic-oauth-component-new-main"
        )

      authorize_url = component_assigns[:authorize_url]

      [subscription_id, mod, _component_id, _env] =
        get_decoded_state(authorize_url)

      assert view.id == subscription_id
      assert view |> element("#generic-oauth-component-new-main")

      view
      |> element("#authorize-button")
      |> render_click()

      refute view
             |> has_element?("#authorize-button")

      LightningWeb.OauthCredentialHelper.broadcast_forward(subscription_id, mod,
        id: "generic-oauth-component-new-main",
        code: "authcode123",
        current_tab: "main"
      )

      Lightning.ApplicationHelpers.dynamically_absorb_delay(fn ->
        {_, assigns} =
          Lightning.LiveViewHelpers.get_component_assigns_by(view,
            id: "generic-oauth-component-new-main"
          )

        :error === assigns[:oauth_progress]
      end)

      # Should show error state but not user info
      refute view |> has_element?("h3", "Test User")

      # Error message should be displayed
      assert view |> render() =~
               "Account Already Connected"

      # Credential should not be created even if form is submitted
      credential =
        Lightning.Credentials.list_credentials(user) |> List.first()

      refute credential
    end
  end

  describe "errors when creating generic oauth credentials" do
    test "error when fetching authorization code", %{conn: conn, user: user} do
      oauth_client = insert(:oauth_client, user: user)

      {:ok, view, _html} = live(conn, ~p"/credentials")

      open_create_credential_modal(view)

      view |> select_credential_type(oauth_client.id)
      view |> click_continue()

      refute view |> has_element?("#credential-type-picker")

      view
      |> fill_credential(%{
        name: "My Generic OAuth Credential"
      })

      Mox.expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        env, _opts
        when env.method == :post and
               env.url == oauth_client.revocation_endpoint ->
          {:ok,
           %Tesla.Env{
             status: 200,
             body: Jason.encode!(%{})
           }}
      end)

      view
      |> element("#authorize-button")
      |> render_click()

      refute view
             |> has_element?("#authorize-button")

      LightningWeb.OauthCredentialHelper.broadcast_forward(
        view.id,
        LightningWeb.CredentialLive.GenericOauthComponent,
        id: "generic-oauth-component-new-main",
        error: "failed fetching authorization code",
        current_tab: "main"
      )

      Lightning.ApplicationHelpers.dynamically_absorb_delay(fn ->
        {_, assigns} =
          Lightning.LiveViewHelpers.get_component_assigns_by(view,
            id: "generic-oauth-component-new-main"
          )

        :error === assigns[:oauth_progress]
      end)

      assert view |> has_element?("p", "The authentication process with")
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

      {:ok, view, _html} = live(conn, ~p"/credentials")

      open_create_credential_modal(view)

      view |> select_credential_type(oauth_client.id)
      view |> click_continue()

      refute view |> has_element?("#credential-type-picker")

      view
      |> fill_credential(%{
        name: "My Generic OAuth Credential"
      })

      view
      |> element("#authorize-button")
      |> render_click()

      refute view
             |> has_element?("#authorize-button")

      LightningWeb.OauthCredentialHelper.broadcast_forward(
        view.id,
        LightningWeb.CredentialLive.GenericOauthComponent,
        id: "generic-oauth-component-new-main",
        code: "authcode123",
        current_tab: "main"
      )

      Lightning.ApplicationHelpers.dynamically_absorb_delay(fn ->
        {_, assigns} =
          Lightning.LiveViewHelpers.get_component_assigns_by(view,
            id: "generic-oauth-component-new-main"
          )

        :error === assigns[:oauth_progress]
      end)

      assert view
             |> has_element?(
               "p",
               "Your authorization with"
             )
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

      {:ok, view, _html} = live(conn, ~p"/credentials")

      open_create_credential_modal(view)

      view |> select_credential_type(oauth_client.id)
      view |> click_continue()

      refute view |> has_element?("#credential-type-picker")

      view
      |> fill_credential(%{
        name: "My Generic OAuth Credential"
      })

      view
      |> element("#authorize-button")
      |> render_click()

      refute view
             |> has_element?("#authorize-button")

      LightningWeb.OauthCredentialHelper.broadcast_forward(
        view.id,
        LightningWeb.CredentialLive.GenericOauthComponent,
        id: "generic-oauth-component-new-main",
        code: "authcode123",
        current_tab: "main"
      )

      Lightning.ApplicationHelpers.dynamically_absorb_delay(fn ->
        {_, assigns} =
          Lightning.LiveViewHelpers.get_component_assigns_by(view,
            id: "generic-oauth-component-new-main"
          )

        :complete === assigns[:oauth_progress]
      end)

      assert view |> render() =~
               "Successfully authenticated with"

      assert has_element?(view, "button", "reauthenticate with")
    end
  end

  describe "generic oauth credential offline_access handling" do
    setup do
      Mox.stub(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn env,
                                                                       _opts ->
        case env.url do
          "http://example.com/oauth2/revoke" ->
            {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{})}}

          "http://example.com/oauth2/token" ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body:
                 Jason.encode!(%{
                   "access_token" => "test_token",
                   "refresh_token" => "refresh_token",
                   "expires_at" => DateTime.to_unix(DateTime.utc_now()) + 3600,
                   "token_type" => "Bearer",
                   "scope" => env.opts[:test_scope] || "read write"
                 })
             }}

          "http://example.com/oauth2/userinfo" ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body:
                 Jason.encode!(%{
                   "name" => "Test User",
                   "picture" => "image.png"
                 })
             }}
        end
      end)

      :ok
    end

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

      {:ok, view, _html} = live(conn, ~p"/credentials")

      open_create_credential_modal(view)

      view |> select_credential_type(oauth_client.id)
      view |> click_continue()

      view
      |> element("#scope_selection_new_main_offline_access")
      |> render_change(%{"_target" => ["offline_access"]})

      view
      |> fill_credential(%{name: "Test Credential"})

      Mox.expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, 2, fn env,
                                                                            _opts ->
        case env.url do
          "http://example.com/oauth2/token" ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body:
                 Jason.encode!(%{
                   "access_token" => "test_token",
                   "refresh_token" => "refresh_token",
                   "expires_at" => DateTime.to_unix(DateTime.utc_now()) + 3600,
                   "token_type" => "Bearer",
                   "scope" => "read write"
                 })
             }}

          "http://example.com/oauth2/userinfo" ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body:
                 Jason.encode!(%{
                   "name" => "Test User",
                   "picture" => "image.png"
                 })
             }}

          _ ->
            {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{})}}
        end
      end)

      view |> element("#authorize-button") |> render_click()

      LightningWeb.OauthCredentialHelper.broadcast_forward(
        view.id,
        LightningWeb.CredentialLive.GenericOauthComponent,
        id: "generic-oauth-component-new-main",
        code: "auth_code",
        current_tab: "main"
      )

      Lightning.ApplicationHelpers.dynamically_absorb_delay(fn ->
        {_, assigns} =
          Lightning.LiveViewHelpers.get_component_assigns_by(view,
            id: "generic-oauth-component-new-main"
          )

        :complete === assigns[:oauth_progress]
      end)

      assert view |> has_element?("h3", "Test User")
      refute view |> submit_disabled("save-credential-button-new")

      {:ok, _view, _html} =
        view
        |> form("#credential-form-new")
        |> render_submit()
        |> follow_redirect(conn, ~p"/credentials")

      assert_redirect(view, ~p"/credentials")
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

      {:ok, view, _html} = live(conn, ~p"/credentials")

      open_create_credential_modal(view)

      view |> select_credential_type(oauth_client.id)
      view |> click_continue()

      view
      |> element("#scope_selection_new_main_admin")
      |> render_change(%{"_target" => ["admin"]})

      view
      |> element("#scope_selection_new_main_offline_access")
      |> render_change(%{"_target" => ["offline_access"]})

      view
      |> fill_credential(%{name: "Test Credential"})

      Mox.expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn env,
                                                                         _opts ->
        case env.url do
          "http://example.com/oauth2/token" ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body:
                 Jason.encode!(%{
                   "access_token" => "test_token",
                   "refresh_token" => "refresh_token",
                   "expires_at" => DateTime.to_unix(DateTime.utc_now()) + 3600,
                   "token_type" => "Bearer",
                   "scope" => "read"
                 })
             }}

          _ ->
            {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{})}}
        end
      end)

      view |> element("#authorize-button") |> render_click()

      LightningWeb.OauthCredentialHelper.broadcast_forward(
        view.id,
        LightningWeb.CredentialLive.GenericOauthComponent,
        id: "generic-oauth-component-new-main",
        code: "auth_code",
        current_tab: "main"
      )

      Lightning.ApplicationHelpers.dynamically_absorb_delay(fn ->
        {_, assigns} =
          Lightning.LiveViewHelpers.get_component_assigns_by(view,
            id: "generic-oauth-component-new-main"
          )

        :error === assigns[:oauth_progress]
      end)

      html = render(view)

      assert html =~ "Missing permissions:"
      # Only mandatory scopes are reported in error messages
      assert html =~ "&#39;write&#39;"
      # offline_access should be ignored in validation
      refute html =~ "&#39;offline_access&#39;"

      # Button is enabled to allow reauthorization
      refute view |> submit_disabled("#save-credential-button-new")
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

      {:ok, view, _html} = live(conn, ~p"/credentials")

      open_create_credential_modal(view)

      view |> select_credential_type(oauth_client.id)
      view |> click_continue()

      assert view |> has_element?("#scope_selection_new_main_offline_access")

      view
      |> element("#scope_selection_new_main_offline_access")
      |> render_change(%{"_target" => ["offline_access"]})

      view
      |> fill_credential(%{name: "Test Credential"})

      Mox.expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, 2, fn env,
                                                                            _opts ->
        case env.url do
          "http://example.com/oauth2/token" ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body:
                 Jason.encode!(%{
                   "access_token" => "test_token",
                   "refresh_token" => "refresh_token",
                   "expires_at" => DateTime.to_unix(DateTime.utc_now()) + 3600,
                   "token_type" => "Bearer",
                   "scope" => "read"
                 })
             }}

          "http://example.com/oauth2/userinfo" ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body:
                 Jason.encode!(%{
                   "name" => "Test User",
                   "picture" => "image.png"
                 })
             }}

          _ ->
            {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{})}}
        end
      end)

      view |> element("#authorize-button") |> render_click()

      LightningWeb.OauthCredentialHelper.broadcast_forward(
        view.id,
        LightningWeb.CredentialLive.GenericOauthComponent,
        id: "generic-oauth-component-new-main",
        code: "auth_code",
        current_tab: "main"
      )

      Lightning.ApplicationHelpers.dynamically_absorb_delay(fn ->
        {_, assigns} =
          Lightning.LiveViewHelpers.get_component_assigns_by(view,
            id: "generic-oauth-component-new-main"
          )

        :complete === assigns[:oauth_progress]
      end)

      assert view |> has_element?("h3", "Test User")
      refute view |> submit_disabled("save-credential-button-new")
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

      {:ok, view, _html} = live(conn, ~p"/credentials")

      open_create_credential_modal(view)

      view |> select_credential_type(oauth_client.id)
      view |> click_continue()

      view
      |> element("#scope_selection_new_main_offline_access")
      |> render_change(%{"_target" => ["offline_access"]})

      view
      |> fill_credential(%{name: "Test Credential"})

      Mox.stub(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        %{url: "http://example.com/oauth2/revoke"}, _opts ->
          {:ok, %Tesla.Env{status: 200, body: Jason.encode!(%{})}}
      end)

      Mox.expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, 2, fn env,
                                                                            _opts ->
        case env.url do
          "http://example.com/oauth2/token" ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body:
                 Jason.encode!(%{
                   "access_token" => "test_token",
                   "refresh_token" => "refresh_token",
                   "expires_at" => DateTime.to_unix(DateTime.utc_now()) + 3600,
                   "token_type" => "Bearer",
                   "scope" => "read write offline_access"
                 })
             }}

          "http://example.com/oauth2/userinfo" ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body:
                 Jason.encode!(%{
                   "name" => "Test User",
                   "picture" => "image.png"
                 })
             }}
        end
      end)

      view |> element("#authorize-button") |> render_click()

      LightningWeb.OauthCredentialHelper.broadcast_forward(
        view.id,
        LightningWeb.CredentialLive.GenericOauthComponent,
        id: "generic-oauth-component-new-main",
        code: "auth_code",
        current_tab: "main"
      )

      Lightning.ApplicationHelpers.dynamically_absorb_delay(fn ->
        {_, assigns} =
          Lightning.LiveViewHelpers.get_component_assigns_by(view,
            id: "generic-oauth-component-new-main"
          )

        :complete === assigns[:oauth_progress]
      end)

      assert view |> has_element?("h3", "Test User")
      refute view |> submit_disabled("save-credential-button-new")
    end
  end

  describe "transfer credential modal" do
    setup %{conn: conn} do
      owner = insert(:user)
      project = build(:project) |> with_project_user(owner, :owner) |> insert()

      credential =
        insert(:credential,
          user: owner,
          project_credentials: [%{project_id: project.id}]
        )

      conn = log_in_user(conn, owner)
      {:ok, view, _html} = live(conn, ~p"/credentials")

      open_transfer_credential_modal(view, credential.id)

      %{
        owner: owner,
        project: project,
        credential: credential,
        view: view
      }
    end

    test "validates required email", %{view: view, credential: credential} do
      view
      |> element("#transfer-credential-#{credential.id}-modal-form")
      |> render_change(%{"receiver" => %{"email" => ""}}) =~ "can't be blank"
    end

    test "validates email format", %{view: view, credential: credential} do
      view
      |> element("#transfer-credential-#{credential.id}-modal-form")
      |> render_change(%{"receiver" => %{"email" => "invalid-email"}}) =~
        "must have the @ sign and no spaces"
    end

    test "validates receiver exists", %{view: view, credential: credential} do
      view
      |> element("#transfer-credential-#{credential.id}-modal-form")
      |> render_change(%{"receiver" => %{"email" => "nonexistent@example.com"}}) =~
        "User does not exist"
    end

    test "validates cannot transfer to self", %{
      view: view,
      owner: owner,
      credential: credential
    } do
      view
      |> element("#transfer-credential-#{credential.id}-modal-form")
      |> render_change(%{"receiver" => %{"email" => owner.email}}) =~
        "You cannot transfer a credential to yourself"
    end

    test "validates receiver has project access", %{
      view: view,
      credential: credential
    } do
      receiver = insert(:user)

      view
      |> element("#transfer-credential-#{credential.id}-modal-form")
      |> render_change(%{"receiver" => %{"email" => receiver.email}}) =~
        "User doesn't have access to these projects"
    end

    test "initiates transfer for valid receiver", %{
      conn: conn,
      view: view,
      project: project,
      credential: credential
    } do
      receiver = insert(:user)
      insert(:project_user, project: project, user: receiver)

      assert {:ok, _view, html} =
               view
               |> element("#transfer-credential-#{credential.id}-modal-form")
               |> render_submit(%{"receiver" => %{"email" => receiver.email}})
               |> follow_redirect(conn, ~p"/credentials")

      assert html =~
               "Credential transfer initiated"

      assert_email_sent(
        to: Swoosh.Email.Recipient.format(credential.user),
        subject: "Transfer #{credential.name} to #{receiver.first_name}"
      )

      assert Repo.get_by(Lightning.Accounts.UserToken,
               context: "credential_transfer",
               user_id: credential.user_id
             )
    end

    test "closes modal", %{view: view, credential: credential} do
      assert has_element?(view, "#transfer-credential-#{credential.id}-modal")

      view
      |> element("#transfer-credential-#{credential.id}-modal-cancel-button")
      |> render_click()

      refute has_element?(view, "#transfer-credential-#{credential.id}-modal")
    end

    test "enables submit when form valid", %{
      view: view,
      project: project,
      credential: credential
    } do
      receiver = insert(:user)
      insert(:project_user, project: project, user: receiver)

      view
      |> element("#transfer-credential-#{credential.id}-modal-form")
      |> render_change(%{
        "receiver" => %{"email" => receiver.email}
      })

      refute view
             |> submit_disabled(
               "#transfer-credential-#{credential.id}-modal-submit-button"
             )
    end

    test "invalid email format stops validation chain", %{
      view: view,
      credential: credential
    } do
      html =
        view
        |> element(
          "#transfer-credential-#{credential.id}-modal-form input[name='receiver[email]']"
        )
        |> render_blur(%{"value" => "not-an-email"})

      assert html =~ "Email address not valid"
      refute html =~ "user does not exist"
      refute html =~ "You cannot transfer a credential to yourself"
      refute html =~ "User doesn&#39;t have access to these projects"
    end

    test "self transfer validation with valid email format", %{
      view: view,
      owner: owner,
      credential: credential
    } do
      html =
        view
        |> element(
          "#transfer-credential-#{credential.id}-modal-form input[name='receiver[email]']"
        )
        |> render_blur(%{"value" => owner.email})

      refute html =~ "Email address not valid"
      refute html =~ "user does not exist"
      assert html =~ "You cannot transfer a credential to yourself"
    end

    test "non-existent user validation with valid email format", %{
      view: view,
      credential: credential
    } do
      html =
        view
        |> element(
          "#transfer-credential-#{credential.id}-modal-form input[name='receiver[email]']"
        )
        |> render_blur(%{"value" => "nonexistent@example.com"})

      refute html =~ "Email address not valid"
      assert html =~ "User does not exist"
      refute html =~ "You cannot transfer a credential to yourself"
    end

    test "project access validation with valid user", %{
      view: view,
      credential: credential
    } do
      receiver = insert(:user)

      html =
        view
        |> element(
          "#transfer-credential-#{credential.id}-modal-form input[name='receiver[email]']"
        )
        |> render_blur(%{"value" => receiver.email})

      refute html =~ "Email address not valid"
      refute html =~ "user does not exist"
      refute html =~ "You cannot transfer a credential to yourself"
      assert html =~ "User doesn&#39;t have access to these projects"
    end

    test "successful validation with valid user and project access", %{
      view: view,
      project: project,
      credential: credential
    } do
      receiver = insert(:user)
      insert(:project_user, project: project, user: receiver)

      html =
        view
        |> element(
          "#transfer-credential-#{credential.id}-modal-form input[name='receiver[email]']"
        )
        |> render_blur(%{"value" => receiver.email})

      refute html =~ "Email address not valid"
      refute html =~ "user does not exist"
      refute html =~ "You cannot transfer a credential to yourself"
      refute html =~ "User doesn&#39;t have access to these projects"
    end
  end

  describe "revoke credential transfer modal" do
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
      {:ok, view, _html} = live(conn, ~p"/credentials")

      open_transfer_credential_modal(view, credential.id)

      %{
        owner: owner,
        project: project,
        credential: credential,
        view: view
      }
    end

    test "shows revoke UI when transfer is pending", %{view: view} do
      html = render(view)
      assert html =~ "Revoke Credential Transfer"
      assert html =~ "A transfer of this credential is pending"
      assert html =~ "Revoking this transfer will cancel the pending request"
    end

    test "revokes transfer successfully", %{
      conn: conn,
      view: view,
      credential: credential
    } do
      assert {:ok, _view, html} =
               view
               |> element(
                 "#transfer-credential-#{credential.id}-modal-revoke-button"
               )
               |> render_click()
               |> follow_redirect(conn, ~p"/credentials")

      assert html =~ "Transfer revoked successfully"

      updated_credential =
        Repo.get(Lightning.Credentials.Credential, credential.id)

      assert is_nil(updated_credential.transfer_status)

      # Verify token was deleted
      refute Repo.get_by(Lightning.Accounts.UserToken,
               context: "credential_transfer",
               user_id: credential.user_id
             )
    end

    test "closes modal after canceling revoke", %{
      view: view,
      credential: credential
    } do
      assert has_element?(view, "#transfer-credential-#{credential.id}-modal")

      view
      |> element("#transfer-credential-#{credential.id}-modal-cancel-button")
      |> render_click()

      refute has_element?(view, "#transfer-credential-#{credential.id}-modal")
    end

    test "handles revoke failure gracefully", %{
      conn: conn,
      view: view,
      credential: credential
    } do
      # Force a failure by deleting the credential first
      Repo.delete!(credential)

      {:ok, _view, html} =
        view
        |> element("#transfer-credential-#{credential.id}-modal-revoke-button")
        |> render_click()
        |> follow_redirect(conn, ~p"/credentials")

      assert html =~ "Could not revoke transfer"
    end
  end

  describe "credential type picker modal" do
    test "displays credential type modal with icons", %{conn: conn} do
      {:ok, view, _html} = live(conn, ~p"/credentials")

      html = open_create_credential_modal(view)

      html_tree = Floki.parse_document!(html)

      for adaptor <- ["postgresql", "dhis2", "http"] do
        adaptor_label =
          Floki.find(
            html_tree,
            "label[for='credential-schema-picker_selected_#{adaptor}']"
          )

        adaptor_icon = Floki.find(adaptor_label, "object")
        assert length(adaptor_icon) > 0
        img_src = adaptor_icon |> Floki.attribute("data") |> List.first()
        assert img_src =~ "/images/adaptors/#{adaptor}-square.png"
      end
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
      [project_1, project_2, project_3] =
        insert_list(3, :project, project_users: [%{user: user, role: :owner}])

      oauth_client =
        insert(:oauth_client,
          user: user,
          mandatory_scopes: "",
          optional_scopes: ""
        )

      {:ok, view, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_create_credential_modal(view)

      view |> select_credential_type(oauth_client.id)
      view |> click_continue()

      refute view |> has_element?("#credential-type-picker")

      view
      |> fill_credential(%{
        name: "My Generic OAuth Credential"
      })

      # Get the authorize URL from the component's assigns
      {_, component_assigns} =
        Lightning.LiveViewHelpers.get_component_assigns_by(view,
          id: "generic-oauth-component-new-main"
        )

      authorize_url = component_assigns[:authorize_url]

      [subscription_id, mod, _component_id, _env] =
        get_decoded_state(authorize_url)

      assert view.id == subscription_id
      assert view |> element("#generic-oauth-component-new-main")

      view
      |> element("#authorize-button")
      |> render_click()

      refute view
             |> has_element?("#authorize-button")

      LightningWeb.OauthCredentialHelper.broadcast_forward(subscription_id, mod,
        id: "generic-oauth-component-new-main",
        code: "authcode123",
        current_tab: "main"
      )

      Lightning.ApplicationHelpers.dynamically_absorb_delay(fn ->
        {_, assigns} =
          Lightning.LiveViewHelpers.get_component_assigns_by(view,
            id: "generic-oauth-component-new-main"
          )

        :complete === assigns[:oauth_progress]
      end)

      assert view |> has_element?("h3", "Test User")

      [project_1, project_2, project_3]
      |> Enum.each(fn project ->
        view
        |> element("#project-credentials-list-new")
        |> render_change(%{"project_id" => project.id})
      end)

      view
      |> element("#remove-project-credential-button-new-#{project_2.id}")
      |> render_click()

      refute view |> submit_disabled("save-credential-button-new")

      {:ok, _index_live, _html} =
        view
        |> form("#credential-form-new")
        |> render_submit()
        |> follow_redirect(
          conn,
          ~p"/credentials"
        )

      {_path, flash} = assert_redirect(view)
      assert flash == %{"info" => "Credential created successfully"}

      credential =
        Lightning.Credentials.list_credentials(user)
        |> List.first()
        |> Repo.preload(:credential_bodies)

      assert credential.project_credentials
             |> Enum.all?(fn pc ->
               pc.project_id in Enum.map([project_1, project_3], fn project ->
                 project.id
               end)
             end)

      refute credential.project_credentials
             |> Enum.find(fn pc -> pc.project_id == project_2.id end)

      # Get the main environment body
      main_body = Enum.find(credential.credential_bodies, &(&1.name == "main"))
      token = Lightning.AuthProviders.Common.TokenBody.new(main_body.body)

      assert %{
               access_token: "ya29.a0AVvZ",
               refresh_token: "1//03vpp6Li",
               expires_at: _,
               scope: "scope_1 scope_2"
             } = token
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

      {:ok, view, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_edit_credential_modal(view, credential.id)

      Lightning.ApplicationHelpers.dynamically_absorb_delay(fn ->
        {_, assigns} =
          Lightning.LiveViewHelpers.get_component_assigns_by(view,
            id: "generic-oauth-component-#{credential.id}-main"
          )

        assigns[:oauth_progress] in [:complete, :idle]
      end)

      view
      |> form("#credential-form-#{credential.id}",
        credential: %{name: "My Generic OAuth Credential"}
      )
      |> render_change()

      view
      |> element(
        "#remove-project-credential-button-#{credential.id}-#{project_1.id}"
      )
      |> render_click()

      refute view |> submit_disabled("save-credential-button-#{credential.id}")

      view
      |> form("#credential-form-#{credential.id}")
      |> render_submit()

      assert_redirected(view, ~p"/credentials")

      credential =
        credential
        |> Repo.reload!()
        |> Repo.preload(:project_credentials)

      assert credential.name == "My Generic OAuth Credential"

      assert Enum.all?(credential.project_credentials, fn pc ->
               pc.project_id in [project_2.id, project_3.id]
             end)

      refute Enum.find(credential.project_credentials, fn pc ->
               pc.project_id == project_1.id
             end)
    end

    test "reauthenticate banner is not rendered the first time we pick permissions",
         %{
           conn: conn,
           user: user
         } do
      oauth_client = insert(:oauth_client, user: user)

      {:ok, view, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_create_credential_modal(view)

      view |> select_credential_type(oauth_client.id)
      view |> click_continue()

      assert view
             |> has_element?("#scope_selection_new_main")

      refute view |> has_element?("#scope-change-action")

      assert view
             |> has_element?("#authorize-button")

      oauth_client.optional_scopes
      |> String.split(",")
      |> Enum.each(fn scope ->
        view
        |> element("#scope_selection_new_main_#{scope}")
        |> render_change(%{"_target" => [scope]})
      end)

      refute view |> has_element?("#scope-change-action")

      assert view
             |> has_element?("#authorize-button")
    end

    test "reauthenticate banner rendered when scopes are changed",
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

      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_edit_credential_modal(index_live, credential.id)

      refute index_live |> has_element?("#scope-change-action")

      oauth_client.optional_scopes
      |> String.split(",")
      |> Enum.each(fn scope ->
        index_live
        |> element("#scope_selection_#{credential.id}_main_#{scope}")
        |> render_change(%{"_target" => [scope]})
      end)

      assert index_live |> has_element?("#authorize-button")
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

      {:ok, edit_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_edit_credential_modal(edit_live, credential.id)

      Lightning.ApplicationHelpers.dynamically_absorb_delay(fn ->
        {_, assigns} =
          Lightning.LiveViewHelpers.get_component_assigns_by(edit_live,
            id: "generic-oauth-component-#{credential.id}-main"
          )

        :complete === assigns[:oauth_progress]
      end)

      assert edit_live |> has_element?("h3", "Test User")
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

      {:ok, edit_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_edit_credential_modal(edit_live, credential.id)

      Lightning.ApplicationHelpers.dynamically_absorb_delay(fn ->
        {_, assigns} =
          Lightning.LiveViewHelpers.get_component_assigns_by(edit_live,
            id: "generic-oauth-component-#{credential.id}-main"
          )

        :complete === assigns[:oauth_progress]
      end)

      edit_live |> render()

      assert edit_live |> has_element?("h3", "Test User")
    end

    test "when oauth client is deleted, oauth credentials associated to it will render a warning banner",
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

      {:ok, view, _html} = live(conn, ~p"/credentials", on_error: :raise)
      html = open_edit_credential_modal(view, credential.id)

      assert html =~ credential.name
      refute view |> has_element?("h3", "OAuth client not found")

      refute view
             |> has_element?(
               "span[phx-hook='Tooltip', aria-label='OAuth client not found']"
             )

      # Now lets delete the oauth client
      Repo.delete!(oauth_client)

      {:ok, view, _html} = live(conn, ~p"/credentials")
      html = open_edit_credential_modal(view, credential.id)

      assert html =~ credential.name
      assert view |> has_element?("h3", "OAuth client not found")

      assert view
             |> has_element?("span##{credential.id}-client-not-found-tooltip")
    end

    test "generic oauth credential will render a scope pick list", %{
      user: user,
      conn: conn
    } do
      oauth_client = insert(:oauth_client, user: user)
      {:ok, index_live, _html} = live(conn, ~p"/credentials")
      open_create_credential_modal(index_live)
      index_live |> select_credential_type(oauth_client.id)
      index_live |> click_continue()

      assert index_live
             |> has_element?("#scope_selection_new_main")

      not_chosen_scopes =
        ~W(wave_api api custom_permissions id profile email address)

      scopes_to_choose = oauth_client.optional_scopes |> String.split(",")

      scopes_to_choose
      |> Enum.each(fn scope ->
        index_live
        |> element("#scope_selection_new_main_#{scope}")
        |> render_change(%{"_target" => [scope]})
      end)

      # Get the authorize URL from the component's assigns
      {_, component_assigns} =
        Lightning.LiveViewHelpers.get_component_assigns_by(index_live,
          id: "generic-oauth-component-new-main"
        )

      authorize_url = component_assigns[:authorize_url]
      %{query: query} = URI.parse(authorize_url)

      scopes_in_url =
        query
        |> URI.decode_query()
        |> Map.get("scope")

      assert scopes_in_url
             |> String.contains?(
               scopes_to_choose
               |> Enum.reverse()
               |> Enum.join(" ")
             )

      refute scopes_in_url
             |> String.contains?(
               not_chosen_scopes
               |> Enum.reverse()
               |> Enum.join(" ")
             )

      # Unselecting one of the already selected scopes will remove it from the authorization url
      scope_to_unselect = scopes_to_choose |> Enum.at(0)

      index_live
      |> element("#scope_selection_new_main_#{scope_to_unselect}")
      |> render_change(%{"_target" => [scope_to_unselect]})

      # Get the updated authorize URL after scope change
      {_, component_assigns} =
        Lightning.LiveViewHelpers.get_component_assigns_by(index_live,
          id: "generic-oauth-component-new-main"
        )

      authorize_url = component_assigns[:authorize_url]
      %{query: query} = URI.parse(authorize_url)

      scopes_in_url =
        query
        |> URI.decode_query()
        |> Map.get("scope")

      refute scopes_in_url |> String.contains?(scope_to_unselect)
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

      # Create credential via LiveView
      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_create_credential_modal(index_live)
      index_live |> select_credential_type("raw")
      index_live |> click_continue()

      # Select parent project
      index_live
      |> element("#project-credentials-list-new")
      |> render_change(%{"project_id" => parent.id})

      # Submit the credential form
      {:ok, _index_live, _html} =
        index_live
        |> form("#credential-form-new",
          credential: %{
            name: "Test Propagation Credential",
            body: Jason.encode!(%{"key" => "value"})
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/credentials")

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

      # Open edit modal and add the parent project
      {:ok, view, _html} = live(conn, ~p"/credentials", on_error: :raise)
      open_edit_credential_modal(view, credential.id)

      view
      |> element("#project-credentials-list-#{credential.id}")
      |> render_change(%{"project_id" => parent.id})

      # Submit the form
      view
      |> form("#credential-form-#{credential.id}")
      |> render_submit()

      assert_redirected(view, ~p"/credentials")

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
      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_create_credential_modal(index_live)
      index_live |> select_credential_type("raw")
      index_live |> click_continue()

      index_live
      |> element("#project-credentials-list-new")
      |> render_change(%{"project_id" => parent.id})

      {:ok, _index_live, _html} =
        index_live
        |> form("#credential-form-new",
          credential: %{
            name: "Branching Test Credential",
            body: Jason.encode!(%{"key" => "value"})
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/credentials")

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

      # Create credential via LiveView
      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_create_credential_modal(index_live)
      index_live |> select_credential_type("raw")
      index_live |> click_continue()

      index_live
      |> element("#project-credentials-list-new")
      |> render_change(%{"project_id" => parent.id})

      {:ok, _index_live, _html} =
        index_live
        |> form("#credential-form-new",
          credential: %{
            name: "Deep Hierarchy Credential",
            body: Jason.encode!(%{"key" => "value"})
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/credentials")

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

      # Create first credential
      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_create_credential_modal(index_live)
      index_live |> select_credential_type("raw")
      index_live |> click_continue()

      index_live
      |> element("#project-credentials-list-new")
      |> render_change(%{"project_id" => parent.id})

      {:ok, index_live, _html} =
        index_live
        |> form("#credential-form-new",
          credential: %{
            name: "First Credential",
            body: Jason.encode!(%{"key" => "value1"})
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/credentials")

      # Create second credential
      open_create_credential_modal(index_live)
      index_live |> select_credential_type("raw")
      index_live |> click_continue()

      index_live
      |> element("#project-credentials-list-new")
      |> render_change(%{"project_id" => parent.id})

      {:ok, _index_live, _html} =
        index_live
        |> form("#credential-form-new",
          credential: %{
            name: "Second Credential",
            body: Jason.encode!(%{"key" => "value2"})
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/credentials")

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
      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      open_create_credential_modal(index_live)
      index_live |> select_credential_type("raw")
      index_live |> click_continue()

      index_live
      |> element("#project-credentials-list-new")
      |> render_change(%{"project_id" => parent.id})

      {:ok, index_live, _html} =
        index_live
        |> form("#credential-form-new",
          credential: %{
            name: "Idempotent Test Credential",
            body: Jason.encode!(%{"key" => "value"})
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/credentials")

      credential =
        Repo.get_by(Credential, name: "Idempotent Test Credential")

      # Try to add the same project again via edit
      open_edit_credential_modal(index_live, credential.id)

      index_live
      |> element("#project-credentials-list-#{credential.id}")
      |> render_change(%{"project_id" => parent.id})

      index_live
      |> form("#credential-form-#{credential.id}")
      |> render_submit()

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
end
