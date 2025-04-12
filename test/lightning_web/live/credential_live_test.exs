defmodule LightningWeb.CredentialLiveTest do
  use LightningWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import LightningWeb.CredentialLiveHelpers

  import Lightning.BypassHelpers
  import Lightning.CredentialsFixtures
  import Lightning.Factories

  import Ecto.Query
  import Swoosh.TestAssertions

  alias Lightning.Accounts.User
  alias Lightning.Credentials
  alias Lightning.Credentials.Credential

  @create_attrs %{
    name: "some credential",
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
      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

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
      assert html =~ "Production"
      assert html =~ credential.schema
      assert html =~ credential.name
    end

    test "lists all credentials for support user", %{
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
      assert html =~ "Production"
      assert html =~ credential.schema
      assert html =~ credential.name
      assert html =~ support_credential.schema
      assert html =~ support_credential.name
    end

    # https://github.com/OpenFn/Lightning/issues/273 - allow users to delete

    test "can schedule for deletion a credential that is not associated to any activity",
         %{
           conn: conn,
           credential: credential
         } do
      {:ok, index_live, html} =
        live(conn, ~p"/credentials/#{credential.id}/delete", on_error: :raise)

      assert html =~ "Delete credential"

      assert html =~
               "Deleting this credential will immediately remove it from all jobs"

      refute html =~ "credential has been used in workflow runs"

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

      assert has_element?(view, "#credentials-#{credential.id}")
    end

    test "can schedule for deletion a credential that is associated to activities",
         %{
           conn: conn,
           credential: credential
         } do
      insert(:step, credential: credential)

      {:ok, index_live, html} =
        live(conn, ~p"/credentials/#{credential.id}/delete", on_error: :raise)

      assert html =~ "Delete credential"

      assert html =~ "Deleting this credential will immediately"
      assert html =~ "*This credential has been used in workflow runs"

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

      assert has_element?(view, "#credentials-#{credential.id}")
    end

    test "cancel a scheduled for deletion credential", %{
      conn: conn,
      credential: credential
    } do
      insert(:step, credential: credential)
      {:ok, credential} = Credentials.schedule_credential_deletion(credential)

      {:ok, index_live, _html} =
        live(conn, ~p"/credentials", on_error: :raise)

      assert index_live
             |> element("#credentials-#{credential.id} a", "Cancel deletion")
             |> has_element?()

      index_live
      |> element("#credentials-#{credential.id} a", "Cancel deletion")
      |> render_click()

      {:ok, index_live, html} = live(conn, ~p"/credentials", on_error: :raise)

      refute html =~ "Cancel deletion"
      refute html =~ "Delete now"

      assert html =~ "Delete"

      assert has_element?(index_live, "#credentials-#{credential.id}")
    end

    test "can delete credential that has no activity in projects", %{
      conn: conn,
      credential: credential
    } do
      {:ok, credential} = Credentials.schedule_credential_deletion(credential)

      {:ok, index_live, html} =
        live(conn, ~p"/credentials/#{credential.id}/delete", on_error: :raise)

      assert html =~
               "Deleting this credential will immediately remove it from all jobs"

      refute html =~ "credential has been used in workflow runs"

      assert index_live
             |> element("button", "Delete credential")
             |> has_element?()

      index_live |> element("button", "Delete credential") |> render_click()

      assert_redirected(index_live, ~p"/credentials")

      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      refute has_element?(index_live, "#credential-#{credential.id}")
    end

    test "cannot delete credential that has activity in projects", %{
      conn: conn,
      credential: credential
    } do
      insert(:step, credential: credential)
      {:ok, credential} = Credentials.schedule_credential_deletion(credential)

      {:ok, index_live, html} =
        live(conn, ~p"/credentials/#{credential.id}/delete", on_error: :raise)

      assert html =~ "This credential has been used in workflow runs"
      assert html =~ "will be made unavailable for future use immediately"

      assert index_live |> element("button", "Ok, understood") |> has_element?()

      index_live |> element("button", "Ok, understood") |> render_click()

      assert_redirected(index_live, ~p"/credentials")

      {:ok, index_live, _html} =
        live(conn, ~p"/credentials", on_error: :raise)

      assert has_element?(index_live, "#credentials-#{credential.id}")
    end

    test "user can only delete their own credential", %{
      conn: conn
    } do
      credential = credential_fixture()

      {:ok, _index_live, html} =
        live(conn, ~p"/credentials/#{credential.id}/delete", on_error: :raise)
        |> follow_redirect(conn, ~p"/credentials")

      assert html =~ "You can&#39;t perform this action"
    end

    test "delete credentials in project settings page", %{
      conn: conn,
      user: user
    } do
      project = insert(:project, project_users: [%{user: user, role: :owner}])

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

      view
      |> element("#delete_credential_#{credential.id}_modal_confirm_button")
      |> render_click() =~ "Credential deleted"

      {:ok, _view, html} =
        live(conn, ~p"/projects/#{project}/settings#credentials",
          on_error: :raise
        )

      refute html =~ credential.name

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

      {:ok, view, html} =
        live(conn, ~p"/projects/#{project}/settings#credentials",
          on_error: :raise
        )

      assert html =~ credential.name

      refute view
             |> has_element?(
               "#delete_credential_#{credential.id}_modal_confirm_button"
             )
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

      index_live |> select_credential_type("raw")
      index_live |> click_continue()

      assert index_live
             |> has_element?(
               "#credential-form-new textarea[name='credential[body]']"
             )

      index_live
      |> element("#project-credentials-list-new")
      |> render_change(%{"project_id" => project1.id})

      index_live
      |> element("#add-project-credential-button-new", "Add")
      |> render_click()

      assert index_live
             |> form("#credential-form-new", credential: %{name: ""})
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#credential-form-new", credential: %{name: "MailChimp'24"})
             |> render_change() =~ "credential name has invalid format"

      index_live
      |> element("#project-credentials-list-new")
      |> render_change(%{"project_id" => project2.id})

      index_live
      |> element("#add-project-credential-button-new", "Add")
      |> render_click()

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

      index_live |> select_credential_type("raw")
      index_live |> click_continue()

      assert index_live
             |> has_element?(
               "#credential-form-new textarea[name='credential[body]']"
             )

      index_live
      |> element("#project-credentials-list-new")
      |> render_change(%{"project_id" => project1.id})

      index_live
      |> element("#add-project-credential-button-new", "Add")
      |> render_click()

      assert index_live
             |> form("#credential-form-new", credential: %{name: ""})
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#credential-form-new", credential: %{name: "MailChimp'24"})
             |> render_change() =~ "credential name has invalid format"

      index_live
      |> element("#project-credentials-list-new")
      |> render_change(%{"project_id" => project2.id})

      index_live
      |> element("#add-project-credential-button-new", "Add")
      |> render_click()

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
      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

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
    end

    test "allows the user to define and save a credential with email (godata)",
         %{
           conn: conn
         } do
      {:ok, view, _html} = live(conn, ~p"/credentials", on_error: :raise)

      select_credential_type(view, "godata")
      click_continue(view)

      assert fill_credential(view, %{body: %{email: ""}}) =~ "can&#39;t be blank"

      assert submit_disabled(view, "#save-credential-button-new")

      assert click_save(view) =~ "can&#39;t be blank"

      refute_redirected(view, ~p"/credentials")

      assert fill_credential(view, %{
               name: "Godata Credential",
               body: %{
                 apiUrl: "http://url",
                 password: "baz1234",
                 email: "incomplete-email"
               }
             }) =~ "expected to be an email"

      assert submit_disabled(view, "#save-credential-button-new")

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

      {:ok, view, _html} = live(conn, ~p"/credentials", on_error: :raise)

      view
      |> element("#project-credentials-list-#{credential.id}")
      |> render_change(%{"project_id" => project.id})

      view
      |> element("#add-project-credential-button-#{credential.id}")
      |> render_click()

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

      refute has_element?(view, "#project-credentials-list-#{credential.id}")
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

      # Try adding an existing project credential
      view
      |> element("#project-credentials-list-#{credential.id}")
      |> render_change(%{"project_id" => project.id})

      html =
        view
        |> element("#add-project-credential-button-#{credential.id}")
        |> render_click()

      assert html =~ project.name,
             "adding an existing project doesn't break anything"

      assert view |> delete_credential_button(project.id) |> has_element?()

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

      view
      |> element("#add-project-credential-button-#{credential.id}")
      |> render_click()

      assert view |> delete_credential_button(project.id) |> has_element?(),
             "project is added back"

      view |> form("#credential-form-#{credential.id}") |> render_submit()

      assert_redirected(view, ~p"/credentials")
    end

    test "marks a credential for use in a 'production' system", %{
      conn: conn,
      credential: credential
    } do
      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

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
  end

  describe "Authorizing an oauth credential" do
    setup do
      {:ok,
       token: %{
         "access_token" => "ya29.a0AVvZ",
         "refresh_token" => "1//03vpp6Li",
         "expires_at" => 3600,
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

      credential =
        insert(:credential,
          user: user,
          schema: "oauth",
          body: %{"apiVersion" => "v1"},
          oauth_token:
            build(:oauth_token,
              body: token,
              user: user,
              oauth_client: oauth_client
            ),
          oauth_client: oauth_client
        )

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
               body: Jason.encode!(token)
             }}
        end
      end)

      {:ok, view, _html} = live(conn, ~p"/credentials", on_error: :raise)

      assert view |> element("#credential-form-#{credential.id}") |> render() =~
               "Success."

      view
      |> element("#credential-form-#{credential.id} #re-authorize-button")
      |> render_click()

      view
      |> element("#credential-form-#{credential.id} button", "Cancel")
      |> render_click()

      Mox.stub(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn env,
                                                                       _opts ->
        case env.url do
          "http://example.com/oauth2/revoke" ->
            {:ok,
             %Tesla.Env{
               status: 400,
               body: Jason.encode!(%{})
             }}

          "http://example.com/oauth2/token" ->
            {:ok,
             %Tesla.Env{
               status: 400,
               body: Jason.encode!(%{})
             }}
        end
      end)

      {:ok, view, _html} = live(conn, ~p"/credentials", on_error: :raise)

      assert view
             |> element("#credential-form-#{credential.id}")
             |> render() =~
               "Failed retrieving the token from the provider. Please try again"

      assert view
             |> element("#credential-form-#{credential.id} #re-authorize-button")
             |> render_click() =~
               "Token revocation failed. The token associated with this credential may have already been revoked or expired. You may try to authorize again, or delete this credential and create a new one"
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
                   "expires_at" => 3600,
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
                 Jason.encode!(%{"picture" => "image.png", "name" => "Test User"})
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

      oauth_client = insert(:oauth_client, user: user)

      {:ok, view, _html} = live(conn, ~p"/credentials", on_error: :raise)

      view |> select_credential_type(oauth_client.id)
      view |> click_continue()

      refute view |> has_element?("#credential-type-picker")

      view
      |> fill_credential(%{
        name: "My Generic OAuth Credential"
      })

      authorize_url =
        view
        |> element("#credential-form-new")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("a[phx-click=authorize_click]")
        |> Floki.attribute("href")
        |> List.first()

      [subscription_id, mod, component_id] = get_decoded_state(authorize_url)

      assert view.id == subscription_id
      assert view |> element(component_id)

      view
      |> element("#authorize-button")
      |> render_click()

      refute view
             |> has_element?("#authorize-button")

      LightningWeb.OauthCredentialHelper.broadcast_forward(subscription_id, mod,
        id: component_id,
        code: "authcode123"
      )

      Lightning.ApplicationHelpers.dynamically_absorb_delay(fn ->
        {_, assigns} =
          Lightning.LiveViewHelpers.get_component_assigns_by(view,
            id: "generic-oauth-component-new"
          )

        :missing_required === assigns[:oauth_progress]
      end)

      refute view |> has_element?("h3", "Test User")

      assert view |> submit_disabled("#save-credential-button-new")

      assert view |> render() =~
               "We didn&#39;t receive a refresh token from this provider."

      credential =
        Lightning.Credentials.list_credentials(user) |> List.first()

      refute credential
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
                   "expires_at" => 3600,
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
                 Jason.encode!(%{"picture" => "image.png", "name" => "Test User"})
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

      oauth_client = insert(:oauth_client, user: user)

      {:ok, view, _html} = live(conn, ~p"/credentials", on_error: :raise)

      view |> select_credential_type(oauth_client.id)
      view |> click_continue()

      refute view |> has_element?("#credential-type-picker")

      view
      |> fill_credential(%{
        name: "My Generic OAuth Credential"
      })

      authorize_url =
        view
        |> element("#credential-form-new")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("a[phx-click=authorize_click]")
        |> Floki.attribute("href")
        |> List.first()

      [subscription_id, mod, component_id] = get_decoded_state(authorize_url)

      assert view.id == subscription_id
      assert view |> element(component_id)

      view
      |> element("#authorize-button")
      |> render_click()

      refute view
             |> has_element?("#authorize-button")

      LightningWeb.OauthCredentialHelper.broadcast_forward(subscription_id, mod,
        id: component_id,
        code: "authcode123"
      )

      Lightning.ApplicationHelpers.dynamically_absorb_delay(fn ->
        {_, assigns} =
          Lightning.LiveViewHelpers.get_component_assigns_by(view,
            id: "generic-oauth-component-new"
          )

        :userinfo_received === assigns[:oauth_progress]
      end)

      assert view |> has_element?("h3", "Test User")

      [project_1, project_2, project_3]
      |> Enum.each(fn project ->
        view
        |> element("#project-credentials-list-new")
        |> render_change(%{"project_id" => project.id})

        view
        |> element("#add-project-credential-button-new", "Add")
        |> render_click()
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
        Lightning.Credentials.list_credentials(user) |> List.first()

      assert credential.project_credentials
             |> Enum.all?(fn pc ->
               pc.project_id in Enum.map([project_1, project_3], fn project ->
                 project.id
               end)
             end)

      refute credential.project_credentials
             |> Enum.find(fn pc -> pc.project_id == project_2.id end)

      token =
        Lightning.AuthProviders.Common.TokenBody.new(credential.oauth_token.body)

      assert %{
               access_token: "ya29.a0AVvZ",
               refresh_token: "1//03vpp6Li",
               expires_at: 3600,
               scope: "scope1 scope2"
             } = token
    end

    test "allow the user to edit an oauth credential", %{
      conn: conn,
      user: user
    } do
      [project_1, project_2, project_3] =
        insert_list(3, :project, project_users: [%{user: user, role: :owner}])

      oauth_client = insert(:oauth_client, user: user)

      oauth_token = %{
        "access_token" => "test_access_token",
        "refresh_token" => "test_refresh_token",
        "token_type" => "bearer",
        "expires_in" => 3600
      }

      credential =
        insert(:credential,
          name: "OAuth credential",
          oauth_client: oauth_client,
          user: user,
          schema: "oauth",
          oauth_token:
            build(:oauth_token,
              body: oauth_token,
              user: user,
              oauth_client: oauth_client
            ),
          project_credentials: [
            %{project: project_1},
            %{project: project_2},
            %{project: project_3}
          ]
        )

      {:ok, view, _html} = live(conn, ~p"/credentials", on_error: :raise)

      view
      |> fill_credential(
        %{
          name: "My Generic OAuth Credential"
        },
        "#credential-form-#{credential.id}"
      )

      view
      |> element(
        "#remove-project-credential-button-#{credential.id}-#{project_1.id}"
      )
      |> render_click()

      refute view |> submit_disabled("save-credential-button-#{credential.id}")

      {:ok, _index_live, _html} =
        view
        |> form("#credential-form-#{credential.id}")
        |> render_submit()
        |> follow_redirect(
          conn,
          ~p"/credentials"
        )

      {_path, flash} = assert_redirect(view)
      assert flash == %{"info" => "Credential updated successfully"}

      credential =
        credential
        |> Repo.reload!()
        |> Repo.preload(:project_credentials)

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

      view |> select_credential_type(oauth_client.id)
      view |> click_continue()

      assert view
             |> has_element?("#scope_selection_new")

      refute view |> has_element?("#re-authorize-banner")

      assert view
             |> has_element?("#authorize-button")

      oauth_client.optional_scopes
      |> String.split(",")
      |> Enum.each(fn scope ->
        view
        |> element("#scope_selection_new_#{scope}")
        |> render_change(%{"_target" => [scope]})
      end)

      refute view |> has_element?("#re-authorize-banner")

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
          body: %{"apiVersion" => "v1"},
          oauth_token:
            build(:oauth_token,
              body: %{
                "access_token" => "access_token",
                "refresh_token" => "refresh_token",
                "expires_at" =>
                  Timex.now() |> Timex.shift(days: 4) |> DateTime.to_unix(),
                "scope" =>
                  String.split(oauth_client.mandatory_scopes, ",")
                  |> Enum.join(" ")
              },
              user: user,
              oauth_client: oauth_client
            ),
          user: user,
          oauth_client: oauth_client
        )

      {:ok, index_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      refute index_live |> has_element?("#re-authorize-banner")

      oauth_client.optional_scopes
      |> String.split(",")
      |> Enum.each(fn scope ->
        index_live
        |> element("#scope_selection_#{credential.id}_#{scope}")
        |> render_change(%{"_target" => [scope]})
      end)

      assert index_live |> has_element?("#re-authorize-banner")
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
          body: %{"apiVersion" => "v1"},
          oauth_token:
            build(:oauth_token,
              body: %{
                "access_token" => "ya29.a0AVvZ...",
                "refresh_token" => "1//03vpp6Li...",
                "expires_at" => expires_at,
                "scope" =>
                  String.split(oauth_client.mandatory_scopes, ",")
                  |> Enum.join(" ")
              },
              user: user,
              oauth_client: oauth_client
            ),
          oauth_client: oauth_client
        )

      {:ok, edit_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      Lightning.ApplicationHelpers.dynamically_absorb_delay(fn ->
        {_, assigns} =
          Lightning.LiveViewHelpers.get_component_assigns_by(edit_live,
            id: "generic-oauth-component-#{credential.id}"
          )

        :userinfo_received === assigns[:oauth_progress]
      end)

      assert edit_live |> has_element?("h3", "Test User")
    end

    test "renewing an expired but valid token", %{
      user: user,
      conn: conn
    } do
      oauth_client = insert(:oauth_client, user: user)

      expires_at = DateTime.to_unix(DateTime.utc_now()) - 50

      credential =
        insert(:credential,
          user: user,
          schema: "oauth",
          body: %{"apiVersion" => "v1"},
          oauth_token:
            build(:oauth_token,
              body: %{
                access_token: "ya29.a0AVvZ...",
                refresh_token: "1//03vpp6Li...",
                expires_at: expires_at,
                scope:
                  String.split(oauth_client.mandatory_scopes, ",")
                  |> Enum.join(" ")
              },
              user: user,
              oauth_client: oauth_client
            ),
          oauth_client_id: oauth_client.id
        )

      {:ok, edit_live, _html} = live(conn, ~p"/credentials", on_error: :raise)

      Lightning.ApplicationHelpers.dynamically_absorb_delay(fn ->
        {_, assigns} =
          Lightning.LiveViewHelpers.get_component_assigns_by(edit_live,
            id: "generic-oauth-component-#{credential.id}"
          )

        :userinfo_received === assigns[:oauth_progress]
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
          user: user,
          oauth_token:
            build(:oauth_token,
              body: %{
                "access_token" => "test_access_token",
                "refresh_token" => "test_refresh_token",
                "token_type" => "bearer",
                "expires_in" => 3600
              },
              user: user,
              oauth_client: oauth_client
            )
        )

      {:ok, view, html} = live(conn, ~p"/credentials", on_error: :raise)

      assert html =~ credential.name
      refute view |> has_element?("h3", "Oauth client not found")

      refute view
             |> has_element?(
               "span[phx-hook='Tooltip', aria-label='OAuth client not found']"
             )

      # Now it's safe to delete the oauth client
      Repo.delete!(oauth_client)

      {:ok, view, html} = live(conn, ~p"/credentials")

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

      index_live |> select_credential_type(oauth_client.id)
      index_live |> click_continue()

      assert index_live
             |> has_element?("#scope_selection_new")

      not_chosen_scopes =
        ~W(wave_api api custom_permissions id profile email address)

      scopes_to_choose = oauth_client.optional_scopes |> String.split(",")

      scopes_to_choose
      |> Enum.each(fn scope ->
        index_live
        |> element("#scope_selection_new_#{scope}")
        |> render_change(%{"_target" => [scope]})
      end)

      %{query: query} =
        index_live
        |> element("#credential-form-new")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("a[phx-click=authorize_click]")
        |> Floki.attribute("href")
        |> List.first()
        |> URI.parse()

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
      |> element("#scope_selection_new_#{scope_to_unselect}")
      |> render_change(%{"_target" => [scope_to_unselect]})

      %{query: query} =
        index_live
        |> element("#credential-form-new")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("a[phx-click=authorize_click]")
        |> Floki.attribute("href")
        |> List.first()
        |> URI.parse()

      scopes_in_url =
        query
        |> URI.decode_query()
        |> Map.get("scope")

      refute scopes_in_url |> String.contains?(scope_to_unselect)
    end

    test "generic oauth credential will render an input for api version",
         %{
           user: user,
           conn: conn
         } do
      oauth_client = insert(:oauth_client, user: user)
      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      index_live |> select_credential_type(oauth_client.id)
      index_live |> click_continue()

      index_live
      |> fill_credential(%{
        name: "My Credential",
        api_version: "34"
      })

      authorize_url =
        index_live
        |> element("#credential-form-new")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("a[phx-click=authorize_click]")
        |> Floki.attribute("href")
        |> List.first()

      [subscription_id, mod, component_id] = get_decoded_state(authorize_url)

      assert index_live.id == subscription_id
      assert index_live |> element(component_id)

      index_live
      |> element("#authorize-button")
      |> render_click()

      refute index_live
             |> has_element?("#authorize-button")

      # `handle_info/2` in LightingWeb.CredentialLive.Edit forwards the data
      # as a `send_update/3` call to the GoogleSheets component
      LightningWeb.OauthCredentialHelper.broadcast_forward(subscription_id, mod,
        id: component_id,
        code: "1234"
      )

      Lightning.ApplicationHelpers.dynamically_absorb_delay(fn ->
        {_, assigns} =
          Lightning.LiveViewHelpers.get_component_assigns_by(index_live,
            id: "generic-oauth-component-new"
          )

        :userinfo_received === assigns[:oauth_progress]
      end)

      assert index_live |> has_element?("h3", "Test User")

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
        Lightning.Credentials.list_credentials(user) |> List.first()

      assert credential.body == %{"apiVersion" => "34"}

      assert %{
               access_token: "ya29.a0AVvZ",
               refresh_token: "1//03vpp6Li",
               expires_at: 3600,
               scope: "scope1 scope2"
             } =
               credential.oauth_token.body
               |> Map.new(fn {k, v} -> {String.to_atom(k), v} end)
    end
  end

  describe "errors when creating generic oauth credentials" do
    test "error when fetching authorization code", %{conn: conn, user: user} do
      oauth_client = insert(:oauth_client, user: user)

      {:ok, view, _html} = live(conn, ~p"/credentials")

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

      authorize_url =
        view
        |> element("#credential-form-new")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("a[phx-click=authorize_click]")
        |> Floki.attribute("href")
        |> List.first()

      [subscription_id, mod, component_id] = get_decoded_state(authorize_url)

      assert view.id == subscription_id
      assert view |> element(component_id)

      view
      |> element("#authorize-button")
      |> render_click()

      refute view
             |> has_element?("#authorize-button")

      LightningWeb.OauthCredentialHelper.broadcast_forward(subscription_id, mod,
        id: component_id,
        error: "failed fetching authorization code"
      )

      Lightning.ApplicationHelpers.dynamically_absorb_delay(fn ->
        {_, assigns} =
          Lightning.LiveViewHelpers.get_component_assigns_by(view,
            id: "generic-oauth-component-new"
          )

        :code_failed === assigns[:oauth_progress]
      end)

      assert view |> has_element?("p", "Failed retrieving authentication code.")
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
            {:error, :unauthorized}

          "http://example.com/oauth2/userinfo" ->
            {:ok,
             %Tesla.Env{
               status: 200,
               body:
                 Jason.encode!(%{"picture" => "image.png", "name" => "Test User"})
             }}
        end
      end)

      oauth_client = insert(:oauth_client, user: user)

      {:ok, view, _html} = live(conn, ~p"/credentials")

      view |> select_credential_type(oauth_client.id)
      view |> click_continue()

      refute view |> has_element?("#credential-type-picker")

      view
      |> fill_credential(%{
        name: "My Generic OAuth Credential"
      })

      authorize_url =
        view
        |> element("#credential-form-new")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("a[phx-click=authorize_click]")
        |> Floki.attribute("href")
        |> List.first()

      [subscription_id, mod, component_id] = get_decoded_state(authorize_url)

      assert view.id == subscription_id
      assert view |> element(component_id)

      view
      |> element("#authorize-button")
      |> render_click()

      refute view
             |> has_element?("#authorize-button")

      LightningWeb.OauthCredentialHelper.broadcast_forward(subscription_id, mod,
        id: component_id,
        code: "authcode123"
      )

      Lightning.ApplicationHelpers.dynamically_absorb_delay(fn ->
        {_, assigns} =
          Lightning.LiveViewHelpers.get_component_assigns_by(view,
            id: "generic-oauth-component-new"
          )

        :token_failed === assigns[:oauth_progress]
      end)

      assert view
             |> has_element?(
               "p",
               "Failed retrieving the token from the provider."
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
                   "expires_at" => 3600,
                   "token_type" => "Bearer",
                   "id_token" => "eyJhbGciO",
                   "scope" => "scope1 scope2"
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

      oauth_client = insert(:oauth_client, user: user)

      {:ok, view, _html} = live(conn, ~p"/credentials")

      view |> select_credential_type(oauth_client.id)
      view |> click_continue()

      refute view |> has_element?("#credential-type-picker")

      view
      |> fill_credential(%{
        name: "My Generic OAuth Credential"
      })

      authorize_url =
        view
        |> element("#credential-form-new")
        |> render()
        |> Floki.parse_fragment!()
        |> Floki.find("a[phx-click=authorize_click]")
        |> Floki.attribute("href")
        |> List.first()

      [subscription_id, mod, component_id] = get_decoded_state(authorize_url)

      assert view.id == subscription_id
      assert view |> element(component_id)

      view
      |> element("#authorize-button")
      |> render_click()

      refute view
             |> has_element?("#authorize-button")

      LightningWeb.OauthCredentialHelper.broadcast_forward(subscription_id, mod,
        id: component_id,
        code: "authcode123"
      )

      Lightning.ApplicationHelpers.dynamically_absorb_delay(fn ->
        {_, assigns} =
          Lightning.LiveViewHelpers.get_component_assigns_by(view,
            id: "generic-oauth-component-new"
          )

        :userinfo_failed === assigns[:oauth_progress]
      end)

      assert view
             |> has_element?(
               "p",
               "That worked, but we couldn't fetch your user information. You can save your credential now or"
             )

      assert has_element?(view, "button", "try again")
    end
  end

  describe "salesforce oauth credential" do
    setup do
      bypass = Bypass.open()

      # TODO: replace this with a proper Mock via Lightning.Config
      Lightning.ApplicationHelpers.put_temporary_env(:lightning, :oauth_clients,
        salesforce: [
          client_id: "foo",
          client_secret: "bar",
          prod_wellknown_url: "http://localhost:#{bypass.port}/auth/.well-known",
          sandbox_wellknown_url:
            "http://localhost:#{bypass.port}/auth/.well-known"
        ]
      )

      {:ok,
       bypass: bypass,
       wellknown_url: "http://localhost:#{bypass.port}/auth/.well-known"}
    end

    # TODO - remove entirely once `salesforce_oauth` is removed.
    @tag :skip
    test "reauthenticate banner is not rendered the first time we pick permissions",
         %{
           bypass: bypass,
           conn: conn,
           user: _user
         } do
      expect_wellknown(bypass)

      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      index_live |> select_credential_type("salesforce_oauth")
      index_live |> click_continue()

      assert index_live
             |> has_element?("#scope_selection_new")

      refute index_live |> has_element?("#reauthorize-banner")
      assert index_live |> has_element?("#authorize-button")

      ~W(cdp_query_api pardot_api cdp_profile_api chatter_api cdp_ingest_api)
      |> Enum.each(fn scope ->
        index_live
        |> element("#scope_selection_new_#{scope}")
        |> render_change(%{"_target" => [scope], "#{scope}" => "on"})
      end)

      refute index_live |> has_element?("#reauthorize-banner")
      assert index_live |> has_element?("#authorize-button")
    end

    # TODO - remove entirely once `salesforce_oauth` is removed.
    @tag :skip
    test "reauthenticate banner rendered when scopes are changed",
         %{
           bypass: bypass,
           conn: conn,
           user: user
         } do
      expect_wellknown(bypass)

      credential =
        insert(:credential,
          name: "my-credential",
          schema: "salesforce_oauth",
          body: %{
            "access_token" => "access_token",
            "refresh_token" => "refresh_token",
            "expires_at" => Timex.now() |> Timex.shift(days: 4),
            "scope" => "cdp_query_api pardot_api cdp_profile_api"
          },
          user: user
        )

      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      index_live |> select_credential_type("salesforce_oauth")
      index_live |> click_continue()

      assert index_live
             |> has_element?("#scope_selection_new")

      refute index_live |> has_element?("#re-authorize-banner")
      refute index_live |> has_element?("#re-authorize-button")

      ~W(chatter_api cdp_ingest_api)
      |> Enum.each(fn scope ->
        index_live
        |> element("#scope_selection_#{credential.id}_#{scope}")
        |> render_change(%{"_target" => [scope], "#{scope}" => "on"})
      end)

      assert index_live |> has_element?("#re-authorize-banner")
      assert index_live |> has_element?("#re-authorize-button")
    end

    test "correctly renders a valid existing token", %{
      conn: conn,
      wellknown_url: wellknown_url,
      user: user,
      bypass: bypass
    } do
      expect_wellknown(bypass)

      expect_userinfo(
        bypass,
        Lightning.AuthProviders.Common.get_wellknown!(wellknown_url),
        %{
          picture: "image.png",
          name: "Test User"
        }
      )

      expires_at = DateTime.to_unix(DateTime.utc_now()) + 3600

      credential =
        credential_fixture(
          user_id: user.id,
          schema: "salesforce_oauth",
          body: %{
            access_token: "ya29.a0AVvZ...",
            refresh_token: "1//03vpp6Li...",
            expires_at: expires_at,
            scope: "scope1 scope2"
          }
        )

      {:ok, edit_live, _html} = live(conn, ~p"/credentials")

      # assert_receive {:phoenix, :send_update, _}

      # Wait for the userinfo endpoint to be called
      assert wait_for_assigns(edit_live, :userinfo_received, credential.id),
             ":userinfo has not been set yet."

      edit_live |> render()

      assert edit_live |> has_element?("h3", "Test User")
    end

    test "renewing an expired but valid token", %{
      user: user,
      bypass: bypass,
      conn: conn
    } do
      # TODO: replace this with a proper Mock via Lightning.Config
      Lightning.ApplicationHelpers.put_temporary_env(:lightning, :oauth_clients,
        salesforce: [
          client_id: "foo",
          client_secret: "bar",
          prod_wellknown_url: "http://localhost:#{bypass.port}/auth/.well-known",
          sandbox_wellknown_url:
            "http://localhost:#{bypass.port}/auth/.well-known"
        ]
      )

      wellknown_url = "http://localhost:#{bypass.port}/auth/.well-known"

      expect_wellknown(bypass)

      expect_userinfo(
        bypass,
        Lightning.AuthProviders.Common.get_wellknown!(wellknown_url),
        """
        {"picture": "image.png", "name": "Test User"}
        """
      )

      expires_at = DateTime.to_unix(DateTime.utc_now()) - 50

      credential =
        credential_fixture(
          user_id: user.id,
          schema: "salesforce_oauth",
          body: %{
            access_token: "ya29.a0AVvZ...",
            refresh_token: "1//03vpp6Li...",
            expires_at: expires_at,
            scope: "scope1 scope2"
          }
        )

      expect_token(
        bypass,
        Lightning.AuthProviders.Common.get_wellknown!(wellknown_url),
        %{
          access_token: "ya29.a0AVvZ...",
          refresh_token: "1//03vpp6Li...",
          expires_at: 3600,
          token_type: "Bearer",
          id_token: "eyJhbGciO...",
          scope: "scope1 scope2"
        }
      )

      expect_introspect(
        bypass,
        Lightning.AuthProviders.Common.get_wellknown!(wellknown_url)
      )

      {:ok, edit_live, _html} = live(conn, ~p"/credentials")

      assert wait_for_assigns(edit_live, :userinfo_received, credential.id),
             ":userinfo has not been set yet."

      edit_live |> render()

      assert edit_live |> has_element?("h3", "Test User")
    end

    @tag :capture_log
    test "failing to retrieve userinfo", %{
      user: user,
      wellknown_url: wellknown_url,
      bypass: bypass,
      conn: conn
    } do
      expect_wellknown(bypass)

      expect_userinfo(
        bypass,
        Lightning.AuthProviders.Common.get_wellknown!(wellknown_url),
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
          schema: "salesforce_oauth",
          body: %{
            access_token: "ya29.a0AVvZ...",
            refresh_token: "1//03vpp6Li...",
            expires_at: expires_at,
            scope: "scope1 scope2",
            instance_url: "http://localhost:#{bypass.port}/salesforce/instance"
          }
        )

      {:ok, edit_live, _html} = live(conn, ~p"/credentials")

      assert wait_for_assigns(edit_live, :userinfo_failed, credential.id)

      edit_live |> render()

      assert edit_live
             |> has_element?(
               "p",
               "That worked, but we couldn't fetch your user information. You can save your credential now or"
             )

      assert has_element?(edit_live, "button", "try again")

      # Now respond with success
      expect_userinfo(
        bypass,
        Lightning.AuthProviders.Common.get_wellknown!(wellknown_url),
        """
        {"picture": "image.png", "name": "Test User"}
        """
      )

      edit_live |> element("button", "try again") |> render_click()

      assert wait_for_assigns(edit_live, :userinfo_received, credential.id)

      assert edit_live |> has_element?("h3", "Test User")
    end

    @tag :capture_log
    test "renewing an expired but invalid token", %{
      user: user,
      wellknown_url: wellknown_url,
      bypass: bypass,
      conn: conn
    } do
      expect_wellknown(bypass)

      expect_token(
        bypass,
        Lightning.AuthProviders.Common.get_wellknown!(wellknown_url),
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
          schema: "salesforce_oauth",
          body: %{
            access_token: "ya29.a0AVvZ...",
            refresh_token: "1//03vpp6Li...",
            expires_at: expires_at,
            scope: "scope1 scope2",
            instance_url: "http://localhost:#{bypass.port}/salesforce/instance"
          }
        )

      {:ok, edit_live, _html} = live(conn, ~p"/credentials")

      assert wait_for_assigns(edit_live, :refresh_failed, credential.id)

      edit_live |> render()

      assert edit_live
             |> has_element?("p", " Failed renewing your access token.")
    end

    # TODO - remove entirely once `salesforce_oauth` is removed.
    @tag :skip
    test "salesforce oauth credential will render a scope pick list", %{
      user: _user,
      bypass: bypass,
      conn: conn
    } do
      # TODO: replace this with a proper Mock via Lightning.Config
      Lightning.ApplicationHelpers.put_temporary_env(:lightning, :oauth_clients,
        google: [client_id: "foo"],
        salesforce: [
          client_id: "foo",
          client_secret: "bar",
          prod_wellknown_url: "http://localhost:#{bypass.port}/auth/.well-known",
          sandbox_wellknown_url:
            "http://localhost:#{bypass.port}/auth/.well-known"
        ]
      )

      expect_wellknown(bypass)

      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      index_live |> select_credential_type("googlesheets")
      index_live |> click_continue()

      refute index_live
             |> has_element?("#inner-form-new-scope-selection")

      {:ok, index_live, _html} = live(conn, ~p"/credentials")

      index_live |> select_credential_type("salesforce_oauth")
      index_live |> click_continue()

      assert index_live
             |> has_element?("#scope_selection_new")

      not_chosen_scopes =
        ~W(wave_api api custom_permissions id profile email address)

      scopes_to_choose =
        ~W(cdp_query_api pardot_api cdp_profile_api chatter_api cdp_ingest_api)

      scopes_to_choose
      |> Enum.each(fn scope ->
        index_live
        |> element("#scope_selection_new_#{scope}")
        |> render_change(%{"_target" => [scope], "#{scope}" => "on"})
      end)

      %{query: query} =
        index_live
        |> get_authorize_url()
        |> URI.parse()

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
      |> element("#scope_selection_new_#{scope_to_unselect}")
      |> render_change(%{"_target" => [scope_to_unselect]})

      %{query: query} =
        index_live
        |> get_authorize_url()
        |> URI.parse()

      scopes_in_url =
        query
        |> URI.decode_query()
        |> Map.get("scope")

      refute scopes_in_url |> String.contains?(scope_to_unselect)
    end

    test "update a prod salesforce credential to turn into a sandbox one", %{
      user: user,
      bypass: bypass,
      conn: conn
    } do
      # TODO: replace this with a proper Mock via Lightning.Config
      Lightning.ApplicationHelpers.put_temporary_env(:lightning, :oauth_clients,
        google: [client_id: "foo"],
        salesforce: [
          client_id: "foo",
          client_secret: "bar",
          prod_wellknown_url: "http://localhost:#{bypass.port}/auth/.well-known",
          sandbox_wellknown_url:
            "http://localhost:#{bypass.port}/auth/.well-known"
        ]
      )

      expect_wellknown(bypass)

      expect_token(
        bypass,
        Lightning.AuthProviders.Common.get_wellknown!(
          "http://localhost:#{bypass.port}/auth/.well-known"
        ),
        %{
          access_token: "ya29.a0AVvZ...",
          refresh_token: "1//03vpp6Li...",
          expires_at: 3600,
          token_type: "Bearer",
          id_token: "eyJhbGciO...",
          scope: "scope1 scope2"
        }
      )

      expect_userinfo(
        bypass,
        Lightning.AuthProviders.Common.get_wellknown!(
          "http://localhost:#{bypass.port}/auth/.well-known"
        ),
        """
        {"picture": "image.png", "name": "Test User"}
        """
      )

      expect_introspect(
        bypass,
        Lightning.AuthProviders.Common.get_wellknown!(
          "http://localhost:#{bypass.port}/auth/.well-known"
        ),
        %{
          access_token: "ya29.a0AVvZ...",
          refresh_token: "1//03vpp6Li...",
          expires_at: 3600,
          token_type: "Bearer",
          id_token: "eyJhbGciO...",
          scope: "scope1 scope2"
        }
      )

      credential =
        insert(:credential,
          schema: "salesforce_oauth",
          user: user,
          body: %{
            access_token: "ya29.a0AVvZ...",
            refresh_token: "1//03vpp6Li...",
            expires_at: 3600,
            scope: "scope1 scope2",
            instance_url: "login.salesforce.com",
            sandbox: false
          }
        )

      token_body = Lightning.AuthProviders.Common.TokenBody.new(credential.body)

      assert token_body.instance_url == "login.salesforce.com"
      assert token_body.sandbox == false

      {:ok, view, _html} = live(conn, ~p"/credentials")

      assert view |> has_element?("#credential-form-#{credential.id}")

      view
      |> element("#salesforce_sandbox_instance_checkbox_#{credential.id}")
      |> render_change(%{"sandbox" => "true"})

      {:ok, _view, _html} =
        view
        |> form("#credential-form-#{credential.id}")
        |> render_submit()
        |> follow_redirect(
          conn,
          ~p"/credentials"
        )

      {_path, flash} = assert_redirect(view)
      assert flash == %{"info" => "Credential updated successfully"}

      credential = Repo.reload!(credential)

      token_body =
        Lightning.AuthProviders.Common.TokenBody.new(credential.body)

      assert token_body.sandbox
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

      {:ok,
       bypass: bypass,
       wellknown_url: "http://localhost:#{bypass.port}/auth/.well-known"}
    end

    test "correctly renders a valid existing token", %{
      conn: conn,
      wellknown_url: wellknown_url,
      user: user,
      bypass: bypass
    } do
      expect_wellknown(bypass)

      expect_userinfo(
        bypass,
        Lightning.AuthProviders.Common.get_wellknown!(wellknown_url),
        %{
          picture: "image.png",
          name: "Test User"
        }
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

      {:ok, edit_live, _html} = live(conn, ~p"/credentials")

      # Wait for the userinfo endpoint to be called
      assert wait_for_assigns(edit_live, :userinfo_received, credential.id),
             ":userinfo has not been set yet."

      edit_live |> render()

      assert edit_live |> has_element?("h3", "Test User")
    end

    test "renewing an expired but valid token", %{
      user: user,
      wellknown_url: wellknown_url,
      bypass: bypass,
      conn: conn
    } do
      expect_wellknown(bypass)

      expect_userinfo(
        bypass,
        Lightning.AuthProviders.Common.get_wellknown!(wellknown_url),
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

      expect_token(
        bypass,
        Lightning.AuthProviders.Common.get_wellknown!(wellknown_url),
        %{
          access_token: "ya29.a0AVvZ...",
          refresh_token: "1//03vpp6Li...",
          expires_at: 3600,
          token_type: "Bearer",
          id_token: "eyJhbGciO...",
          scope: "scope1 scope2"
        }
      )

      {:ok, edit_live, _html} = live(conn, ~p"/credentials")

      assert wait_for_assigns(edit_live, :userinfo_received, credential.id),
             ":userinfo has not been set yet."

      edit_live |> render()

      assert edit_live |> has_element?("h3", "Test User")
    end

    @tag :capture_log
    test "failing to retrieve userinfo", %{
      user: user,
      wellknown_url: wellknown_url,
      bypass: bypass,
      conn: conn
    } do
      expect_wellknown(bypass)

      expect_userinfo(
        bypass,
        Lightning.AuthProviders.Common.get_wellknown!(wellknown_url),
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

      {:ok, edit_live, _html} = live(conn, ~p"/credentials")

      assert wait_for_assigns(edit_live, :userinfo_failed, credential.id)

      edit_live |> render()

      assert edit_live
             |> has_element?(
               "p",
               "That worked, but we couldn't fetch your user information. You can save your credential now or"
             )

      assert has_element?(edit_live, "button", "try again")

      # Now respond with success
      expect_userinfo(
        bypass,
        Lightning.AuthProviders.Common.get_wellknown!(wellknown_url),
        """
        {"picture": "image.png", "name": "Test User"}
        """
      )

      edit_live |> element("button", "try again") |> render_click()

      assert wait_for_assigns(edit_live, :userinfo_received, credential.id)

      assert edit_live |> has_element?("h3", "Test User")
    end

    @tag :capture_log
    test "renewing an expired but invalid token", %{
      user: user,
      wellknown_url: wellknown_url,
      bypass: bypass,
      conn: conn
    } do
      expect_wellknown(bypass)

      expect_token(
        bypass,
        Lightning.AuthProviders.Common.get_wellknown!(wellknown_url),
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

      {:ok, edit_live, _html} = live(conn, ~p"/credentials")

      assert wait_for_assigns(edit_live, :refresh_failed, credential.id)

      edit_live |> render()

      assert edit_live
             |> has_element?("p", "Failed renewing your access token.")
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
      view
      |> element("#transfer-credential-#{credential.id}-modal-cancel-button")
      |> render_click()

      assert_redirect(view, ~p"/credentials")
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
      view
      |> element("#transfer-credential-#{credential.id}-modal-cancel-button")
      |> render_click()

      assert_redirect(view, ~p"/credentials")
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
    setup do
      # Create test manifest file in the configured location
      Application.ensure_all_started(:lightning)
      adaptor_icons_path = Application.get_env(:lightning, :adaptor_icons_path)
      File.mkdir_p!(adaptor_icons_path)

      # Create a manifest with some test data
      manifest_path = Path.join(adaptor_icons_path, "adaptor_icons.json")

      manifest_content =
        Jason.encode!(%{
          "http" => %{"square" => "/images/http-square.png"},
          "postgresql" => %{"square" => "/images/postgresql-square.png"},
          "dhis2" => %{"square" => nil}
        })

      File.write!(manifest_path, manifest_content)

      on_exit(fn ->
        # Clean up manifest file after the test
        File.rm(manifest_path)
      end)

      :ok
    end

    test "displays credential type modal with icons from manifest", %{conn: conn} do
      {:ok, _view, html} = live(conn, ~p"/credentials")

      html_tree = Floki.parse_document!(html)

      # Check for postgresql with image
      postgresql_label =
        Floki.find(
          html_tree,
          "label[for='credential-schema-picker_selected_postgresql']"
        )

      postgresql_img = Floki.find(postgresql_label, "img")
      assert length(postgresql_img) > 0
      img_src = postgresql_img |> Floki.attribute("src") |> List.first()
      assert img_src =~ "postgresql-square.png"

      # For dhis2, which has nil in the manifest, there should be no img tag
      dhis2_label =
        Floki.find(
          html_tree,
          "label[for='credential-schema-picker_selected_dhis2']"
        )

      dhis2_img = Floki.find(dhis2_label, "img")
      assert Enum.empty?(dhis2_img)
    end

    test "handles missing manifest gracefully", %{conn: conn} do
      # Remove the manifest file to test missing manifest case
      adaptor_icons_path = Application.get_env(:lightning, :adaptor_icons_path)
      manifest_path = Path.join(adaptor_icons_path, "adaptor_icons.json")
      File.rm(manifest_path)

      {:ok, _view, html} = live(conn, ~p"/credentials")

      # Schema types should still be there, just without icons
      assert html =~ "http"
      assert html =~ "postgresql"
      assert html =~ "Raw JSON"
    end
  end

  defp wait_for_assigns(live, key, id) do
    Enum.reduce_while(1..10, nil, fn n, _ ->
      {_mod, assigns} =
        Lightning.LiveViewHelpers.get_component_assigns_by(
          live,
          id: "inner-form-#{id}"
        )

      if key == assigns[:oauth_progress] do
        {:halt, key}
      else
        Process.sleep(n * 10)
        {:cont, nil}
      end
    end)
  end

  defp get_authorize_url(live) do
    live
    |> element("#inner-form-new")
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

  defp submit_disabled(live, id \\ "button") do
    has_element?(live, "#{id}[type=submit][disabled]")
  end
end
