defmodule LightningWeb.CredentialLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.CredentialsFixtures

  alias Lightning.Credentials

  @create_attrs %{
    body: "some body",
    name: "some name"
  }
  @update_attrs %{
    body: "some updated body",
    name: "some updated name"
  }
  @invalid_attrs %{body: nil, name: nil}

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
      credential: credential,
      project_credential: project_credential
    } do
      {:ok, _index_live, html} =
        live(conn, Routes.credential_index_path(conn, :index))

      assert html =~ "Credentials"

      assert html =~
               credential.name |> Phoenix.HTML.Safe.to_iodata() |> to_string()

      [[], project_names] =
        Credentials.list_credentials_for_user(credential.user_id)
        |> Enum.map(fn c ->
          Enum.map(c.projects, fn p -> p.name end)
        end)

      assert html =~ project_names |> Enum.join(", ")

      assert html =~ "Edit"
      assert html =~ "Delete"
      assert html =~ "Production"
    end

    test "saves new credential", %{conn: conn, project: project} do
      {:ok, index_live, _html} =
        live(conn, Routes.credential_index_path(conn, :index))

      {:ok, edit_live, _html} =
        index_live
        |> element("a", "New Credential")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.credential_edit_path(conn, :new)
        )

      assert edit_live
             |> form("#credential-form", credential: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert edit_live
             |> form("#credential-form", credential: @create_attrs)
             |> render_change()

      edit_live
      |> element("#project_list")
      |> render_hook("select_item", %{"id" => project.id})

      edit_live
      |> element("button", "Add")
      |> render_click()

      edit_live
      |> form("#credential-form")
      |> render_submit()
    end

    test "deletes credential in listing", %{conn: conn, credential: credential} do
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
  end

  describe "Edit" do
    setup [:create_credential]

    test "updates credential in listing", %{conn: conn, credential: credential} do
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

      assert form_live
             |> form("#credential-form", credential: @update_attrs)
             |> render_submit() =~ "some updated body"
    end

    test "transfers a credential to a new owner", %{
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

      assert form_live
             |> form("#credential-form",
               credential: Map.put(@update_attrs, :production, true)
             )
             |> render_submit() =~ "some updated body"
    end

    test "updates credential for transfering", %{
      conn: conn,
      credential: credential
    } do
      {:ok, index_live, _html} =
        live(conn, Routes.credential_index_path(conn, :index))

      %{
        id: user_id_1,
        first_name: first_name_1,
        last_name: last_name_1,
        email: email_1
      } = Lightning.AccountsFixtures.user_fixture()

      %{
        id: user_id_2,
        first_name: first_name_2,
        last_name: last_name_2,
        email: email_2
      } = Lightning.AccountsFixtures.user_fixture()

      %{
        id: user_id_3,
        first_name: first_name_3,
        last_name: last_name_3,
        email: email_3
      } = Lightning.AccountsFixtures.user_fixture()

      #   # assert form_live
      #   #        |> form("#credential-form", credential: @update_attrs)
      #   #        |> render_submit() =~ "some updated body"
      # end

      {:ok, %Lightning.Projects.Project{id: project_id}} =
        Lightning.Projects.create_project(%{
          name: "some-name",
          project_users: [%{user_id: user_id_1, user_id: user_id_2}]
        })

      {:ok, form_live, html} =
        index_live
        |> element("#credential-#{credential.id} a", "Edit")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.credential_edit_path(conn, :edit, credential)
        )

      assert html =~ user_id_1
      assert html =~ user_id_2
      assert html =~ user_id_3
    end
  end
end
