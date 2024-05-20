defmodule LightningWeb.OauthClientsLiveTest do
  use LightningWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Lightning.Factories

  import Ecto.Query

  alias Lightning.Credentials.OauthClient
  alias Lightning.OauthClients

  defp update_scopes(view, form_id, target, scopes) do
    Enum.each(scopes, fn scope ->
      view
      |> form(form_id)
      |> render_change(%{
        "_target" => ["oauth_client", target],
        "oauth_client" => %{target => scope}
      })
    end)
  end

  defp assert_scopes(view, scope_type, scopes, assert_func) do
    Enum.each(scopes, fn scope ->
      assert_func.(
        view
        |> element("##{scope_type}-scopes-new-#{scope}")
        |> has_element?()
      )
    end)
  end

  defp refute_scopes(view, scope_type, scopes) do
    assert_scopes(view, scope_type, scopes, &refute/1)
  end

  defp perforom_scopes_management_tests(view) do
    mandatory_scopes_to_add = [
      "scope_1,scope_2,will_be_removed",
      "scope_3 scope_4 will_be_modified",
      "scope_5"
    ]

    optional_scopes_to_add = [
      "scope_6,scope_7,will_be_removed",
      "scope_8 scope_9 will_be_modified",
      "scope_10"
    ]

    update_scopes(
      view,
      "#oauth-client-form-new",
      "mandatory_scopes",
      mandatory_scopes_to_add
    )

    update_scopes(
      view,
      "#oauth-client-form-new",
      "optional_scopes",
      optional_scopes_to_add
    )

    added_mandatory_scopes = [
      "scope_1",
      "scope_2",
      "scope_3",
      "scope_4",
      "will_be_removed",
      "will_be_modified"
    ]

    not_added_mandatory_scopes = ["scope_5"]

    added_optional_scopes = [
      "scope_6",
      "scope_7",
      "scope_8",
      "scope_9",
      "will_be_removed",
      "will_be_modified"
    ]

    not_added_optional_scopes = ["scope_10"]

    assert_scopes(view, "mandatory", added_mandatory_scopes, &assert/1)
    assert_scopes(view, "optional", added_optional_scopes, &assert/1)
    refute_scopes(view, "mandatory", not_added_mandatory_scopes)
    refute_scopes(view, "optional", not_added_optional_scopes)

    [{"mandatory", "will_be_removed"}, {"optional", "will_be_removed"}]
    |> Enum.each(fn {scope_type, scope_value} ->
      view
      |> element("##{scope_type}-scopes-new-#{scope_value} button")
      |> render_click()

      refute view
             |> element("##{scope_type}-scopes-new-#{scope_value}")
             |> has_element?()
    end)

    [{"mandatory", "will_be_modified"}, {"optional", "will_be_modified"}]
    |> Enum.each(fn {scope_type, scope_value} ->
      view
      |> element("##{scope_type}-scopes-new-#{scope_value}")
      |> render_hook("edit_#{scope_type}_scope", %{
        "scope" => scope_value
      })

      assert view
             |> element(
               ~s{#oauth-client-form-new_#{scope_type}_scopes[value="#{scope_value}"]}
             )
             |> has_element?()
    end)

    {view, added_mandatory_scopes, added_optional_scopes}
  end

  def random_name do
    first_name = Enum.random(["Google", "Salesforce", "DHIS2", "MS Graph"])
    "#{first_name} OAuth Client"
  end

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "List" do
    @tag :skip
    test "list all created oauth clients", %{
      conn: conn,
      user: user,
      project: project
    } do
      client =
        insert(:oauth_client,
          user: user,
          project_oauth_clients: [%{project: project}]
        )

      _urls =
        [~p"/credentials", ~p"/projects/#{project}/settings#credentials"]
        |> Enum.each(fn url ->
          {:ok, _view, html} = live(conn, url)

          assert html =~ "Oauth Clients"
          assert html =~ "Projects With Access"

          assert html =~
                   client.name |> Phoenix.HTML.Safe.to_iodata() |> to_string()

          [project_names] =
            OauthClients.list_clients(user)
            |> Enum.sort_by(&(&1.project_oauth_clients |> length))
            |> Enum.map(fn c ->
              Enum.map(c.projects, fn p -> p.name end)
            end)

          assert html =~ project_names |> Enum.join(", ")

          assert html =~ "Edit"
          assert html =~ "Delete"
          assert html =~ client.authorization_endpoint
          assert html =~ client.name
        end)
    end

    @tag :skip
    test "when there's no client, an empty page is display with clickable button",
         %{conn: conn, project: project} do
      _urls =
        [~p"/credentials", ~p"/projects/#{project}/settings#credentials"]
        |> Enum.each(fn url ->
          {:ok, view, html} = live(conn, url)

          assert html =~ "Create a new OAuth client"

          assert view
                 |> element("button#open-create-oauth-client-modal-big-buttton")
                 |> has_element?()
        end)
    end
  end

  describe "Create" do
    setup do
      invalid_client_attrs = %{
        authorization_endpoint: "oauth2/v2/auth",
        token_endpoint: ".com/token"
      }

      valid_client_attrs = %{
        name: random_name(),
        authorization_endpoint: "https://accounts.google.com/o/oauth2/v2/auth",
        token_endpoint: "https://oauth2.googleapis.com/token",
        userinfo_endpoint: "https://openidconnect.googleapis.com/v1/userinfo",
        client_id: "somerandomclientid",
        client_secret: "somesupersecretclientsecret",
        scopes_doc_url:
          "https://developers.google.com/identity/protocols/oauth2/scopes"
      }

      %{
        valid_client_attrs: valid_client_attrs,
        invalid_client_attrs: invalid_client_attrs
      }
    end

    test "closing the modal redirects to index page", %{
      conn: conn,
      project: project
    } do
      [~p"/credentials", ~p"/projects/#{project}/settings#credentials"]
      |> Enum.each(fn url ->
        {:ok, view, _html} = live(conn, url)

        view |> element("#close-oauth-client-modal-form-new") |> render_click()

        assert_redirect(view, url)
      end)
    end

    test "can create a new oauth client", %{
      conn: conn,
      project: project,
      valid_client_attrs: valid_attrs,
      invalid_client_attrs: invalid_attrs
    } do
      _urls =
        [~p"/credentials", ~p"/projects/#{project}/settings#credentials"]
        |> Enum.each(fn url ->
          {:ok, view, _html} = live(conn, url)

          html =
            view
            |> form("#oauth-client-form-new", oauth_client: invalid_attrs)
            |> render_change()

          assert html =~ "This field can&#39;t be blank."
          assert html =~ "must be either a http or https URL"

          {view, added_mandatory_scopes, added_optional_scopes} =
            perforom_scopes_management_tests(view)

          {:ok, _view, html} =
            view
            |> form("#oauth-client-form-new", oauth_client: valid_attrs)
            |> render_submit()
            |> follow_redirect(conn, url)

          assert html =~ valid_attrs.name
          assert html =~ "Oauth client created successfully"

          saved_clients_names =
            Lightning.Repo.all(OauthClient)
            |> Enum.map(fn client -> client.name end)

          assert valid_attrs.name in saved_clients_names

          assert Lightning.Repo.all(OauthClient)
                 |> Enum.map(fn client ->
                   MapSet.subset?(
                     MapSet.new(String.split(client.mandatory_scopes, ",")),
                     MapSet.new(added_mandatory_scopes)
                   ) and
                     MapSet.subset?(
                       MapSet.new(String.split(client.optional_scopes, ",")),
                       MapSet.new(added_optional_scopes)
                     )
                 end)
                 |> Enum.all?()
        end)
    end
  end

  describe "Edit" do
    @tag :skip
    test "updates an oauth client", %{
      conn: conn,
      project: project,
      user: user
    } do
      client =
        insert(:oauth_client,
          user: user,
          project_oauth_clients: [%{project: project}]
        )

      [~p"/credentials", ~p"/projects/#{project}/settings#credentials"]
      |> Enum.each(fn url ->
        {:ok, view, html} = live(conn, url)

        new_authorization_endpoint = "https://openfn.org/oauth2/authorize"

        refute html =~ "Oauth client updated successfully"

        refute client.authorization_endpoint === new_authorization_endpoint

        {:ok, _view, html} =
          view
          |> form("#oauth-client-form-#{client.id}",
            oauth_client: %{
              authorization_endpoint: new_authorization_endpoint
            }
          )
          |> render_submit()
          |> follow_redirect(conn, url)

        client = Lightning.Repo.reload(client)

        assert client.authorization_endpoint === new_authorization_endpoint

        assert html =~ "Oauth client updated successfully"
      end)
    end

    @tag :skip
    test "adds new project with access", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project, project_users: [build(:project_user, user: user)])

      client = insert(:oauth_client, name: "My Oauth Client", user: user)

      audit_events_query =
        from(a in Lightning.Credentials.OauthClientAudit.base_query(),
          where: a.item_id == ^client.id,
          select: {a.event, type(a.changes, :map)}
        )

      assert Lightning.Repo.all(audit_events_query) == []

      {:ok, view, _html} = live(conn, ~p"/credentials")

      view
      |> element("#project-oauth-clients-list-#{client.id}")
      |> render_change(%{"project_id" => project.id})

      view
      |> element("#add-project-oauth-client-button-#{client.id}")
      |> render_click()

      view
      |> form("#oauth-client-form-#{client.id}")
      |> render_submit()

      assert_redirected(view, ~p"/credentials")

      audit_events =
        Lightning.Repo.all(audit_events_query)

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

    @tag :skip
    test "removes project with access", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project, project_users: [build(:project_user, user: user)])

      client = insert(:oauth_client, name: "My Oauth Client", user: user)

      insert(:project_oauth_client, project: project, oauth_client: client)

      audit_events_query =
        from(a in Lightning.Credentials.OauthClientAudit.base_query(),
          where: a.item_id == ^client.id,
          select: {a.event, type(a.changes, :map)}
        )

      assert Lightning.Repo.all(audit_events_query) == []

      {:ok, view, _html} = live(conn, ~p"/credentials")

      view
      |> element(
        "[phx-click='remove_selected_project'][phx-value-project_id='#{project.id}']"
      )
      |> render_click()

      view |> form("#oauth-client-form-#{client.id}") |> render_submit()

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

    @tag :skip
    test "users can add and remove existing project oauth clients successfully",
         %{
           conn: conn,
           user: user
         } do
      project =
        insert(:project, project_users: [build(:project_user, user: user)])

      client = insert(:oauth_client, name: "My Oauth Client", user: user)

      insert(:project_oauth_client, project: project, oauth_client: client)

      {:ok, view, _html} = live(conn, ~p"/credentials")

      view
      |> element("#project-oauth-clients-list-#{client.id}")
      |> render_change(%{"project_id" => project.id})

      html =
        view
        |> element("#add-project-oauth-client-button-#{client.id}")
        |> render_click()

      assert html =~ project.name,
             "adding an existing project doesn't break anything"

      assert view
             |> element(
               "[phx-click='remove_selected_project'][phx-value-project_id='#{project.id}']"
             )
             |> has_element?()

      # Let's remove the project and add it back again

      view
      |> element(
        "[phx-click='remove_selected_project'][phx-value-project_id='#{project.id}']"
      )
      |> render_click()

      refute view
             |> element(
               "[phx-click='remove_selected_project'][phx-value-project_id='#{project.id}']"
             )
             |> has_element?(),
             "project is removed from list"

      # now let's add it back
      view
      |> element("#project-oauth-clients-list-#{client.id}")
      |> render_change(%{"project_id" => project.id})

      view
      |> element("#add-project-oauth-client-button-#{client.id}")
      |> render_click()

      assert view
             |> element(
               "[phx-click='remove_selected_project'][phx-value-project_id='#{project.id}']"
             )
             |> has_element?(),
             "project is added back"

      view |> form("#oauth-client-form-#{client.id}") |> render_submit()

      assert_redirected(view, ~p"/credentials")
    end
  end

  describe "Delete" do
    setup %{conn: conn, user: user, project: project} do
      client =
        insert(:oauth_client,
          project_oauth_clients: [%{project: project}],
          user: user
        )

      {:ok, client: client, conn: conn, user: user, project: project}
    end

    @tag :skip
    test "deletes an oauth client from the user credentials page", %{
      conn: conn,
      user: _user,
      project: _project,
      client: client
    } do
      url = ~p"/credentials"
      perform_oauth_client_deletion_test(conn, url, client)
    end

    @tag :skip
    test "deletes an oauth client from the project settings page", %{
      conn: conn,
      user: _user,
      project: project,
      client: client
    } do
      url = ~p"/projects/#{project}/settings#credentials"
      perform_oauth_client_deletion_test(conn, url, client)
    end

    defp perform_oauth_client_deletion_test(conn, url, client) do
      {:ok, view, html} = live(conn, url)

      assert html =~ client.name

      view
      |> element("#delete_oauth_client_#{client.id}_modal_confirm_button")
      |> render_click()

      {:ok, _view, html} = live(conn, url)

      refute html =~ client.name
      refute Lightning.Repo.get(Lightning.Credentials.OauthClient, client.id)
    end
  end
end
