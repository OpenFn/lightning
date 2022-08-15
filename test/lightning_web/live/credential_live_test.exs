defmodule LightningWeb.CredentialLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.CredentialsFixtures

  alias Lightning.Credentials

  @create_attrs %{
    body: "some body",
    name: "{\"a\":\"secret\"}"
  }

  @update_attrs %{
    body: "{\"a\":\"new_secret\"}",
    name: "some updated name"
  }

  @invalid_attrs %{body: nil, name: "this won't work"}

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

    test "lists all credentials", %{
      conn: conn,
      credential: credential
    } do
      {:ok, _index_live, html} =
        live(conn, Routes.credential_index_path(conn, :index))

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

    test "saves new raw credential", %{conn: conn, project: project} do
      {:ok, index_live, _html} =
        live(conn, Routes.credential_index_path(conn, :index))

      {:ok, new_live, _html} =
        index_live
        |> element("a", "New Credential")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.credential_edit_path(conn, :new)
        )

      refute new_live |> has_element?("#credential-form_body")

      new_live
      |> form("#credential-form", credential: %{schema: "raw"})
      |> render_change()

      assert new_live |> has_element?("#credential-form_body")

      assert new_live
             |> form("#credential-form", credential: %{name: ""})
             |> render_change() =~ "can&#39;t be blank"

      assert new_live
             |> form("#credential-form", credential: @create_attrs)
             |> render_change()

      new_live
      |> element("#project_list")
      |> render_hook("select_item", %{"id" => project.id})

      new_live
      |> element("button", "Add")
      |> render_click()

      new_live
      |> form("#credential-form")
      |> render_submit()
    end

    test "saves new dhis2 credential", %{conn: conn} do
      {:ok, index_live, _html} =
        live(conn, Routes.credential_index_path(conn, :index))

      {:ok, new_live, _html} =
        index_live
        |> element("a", "New Credential")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.credential_edit_path(conn, :new)
        )

      new_live
      |> form("#credential-form", credential: %{schema: "dhis2"})
      |> render_change()

      refute new_live |> has_element?("#credential-form_body")

      assert new_live
             |> form("#credential-form", body: %{username: ""})
             |> render_change() =~ "can&#39;t be blank"

      assert new_live |> submit_disabled()

      assert new_live
             |> form("#credential-form",
               credential: %{name: "My Credential"},
               body: %{username: "foo", password: "bar", hostUrl: "baz"}
             )
             |> render_change() =~ "expected to be a URI"

      assert new_live
             |> form("#credential-form",
               body: %{hostUrl: "http://localhost"}
             )
             |> render_change()

      refute new_live |> submit_disabled()

      {:ok, _index_live, _html} =
        new_live
        |> form("#credential-form")
        |> render_submit()
        |> follow_redirect(
          conn,
          Routes.credential_index_path(conn, :index)
        )
    end

    # https://github.com/OpenFn/Lightning/issues/273 - allow users to delete
    @tag :skip
    test "deletes credential without a shared project", %{
      conn: conn,
      credential: credential
    } do
      {:ok, index_live, _html} =
        live(
          conn,
          Routes.credential_index_path(conn, :index)
        )

      assert index_live
             |> element("#credential-#{credential.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#credential-#{credential.id}")
    end

    # https://github.com/OpenFn/Lightning/issues/273 - allow users to delete
    @tag :skip
    test "deletes a credential with a shared project"
    # displays warning
    # removes project_credential
    # removes from any jobs that are currently using it
  end

  describe "Edit" do
    setup [:create_credential]

    test "updates a credential", %{conn: conn, credential: credential} do
      {:ok, index_live, _html} =
        live(conn, Routes.credential_index_path(conn, :index))

      {:ok, form_live, _} =
        index_live
        |> element("#credential-#{credential.id} a", "Edit")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.credential_edit_path(conn, :edit, credential)
        )

      assert form_live
             |> form("#credential-form", credential: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, index_live, html} =
        form_live
        |> form("#credential-form", credential: @update_attrs)
        |> render_submit()
        |> follow_redirect(
          conn,
          Routes.credential_index_path(conn, :index)
        )

      assert html =~ "some updated name"
    end

    test "marks a credential for use in a 'production' system", %{
      conn: conn,
      credential: credential
    } do
      {:ok, index_live, _html} =
        live(conn, Routes.credential_index_path(conn, :index))

      {:ok, form_live, _} =
        index_live
        |> element("#credential-#{credential.id} a", "Edit")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.credential_edit_path(conn, :edit, credential)
        )

      {:ok, index_live, html} =
        form_live
        |> form("#credential-form",
          credential: Map.put(@update_attrs, :production, true)
        )
        |> render_submit()
        |> follow_redirect(
          conn,
          Routes.credential_index_path(conn, :index)
        )

      assert html =~ "some updated name"
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
          project_users: [%{user_id: first_owner.id, user_id: user_2.id}]
        })

      credential =
        credential_fixture(
          user_id: first_owner.id,
          name: "the one for giving away",
          project_credentials: [
            %{project_id: project_id}
          ]
        )

      {:ok, index_live, html} =
        live(conn, Routes.credential_index_path(conn, :index))

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

      {:ok, index_live, html} =
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
          Routes.credential_index_path(conn, :index)
        )

      # Once the transfer is made, the credential should not show up in the list
      assert html =~ "some name"
      refute html =~ "the one for giving away"
    end
  end

  defp submit_disabled(live) do
    live |> has_element?("button[disabled][type=submit]")
  end
end
