defmodule LightningWeb.CredentialLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.CredentialsFixtures

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

  setup :register_and_log_in_user
  setup :create_project_for_current_user

  describe "Index" do
    setup [:create_credential]

    test "lists all credentials", %{
      conn: conn,
      credential: credential
    } do
      {:ok, _index_live, html} =
        live(conn, Routes.credential_index_path(conn, :index))

      assert html =~ "Credentials"

      assert html =~
               credential.body |> Phoenix.HTML.Safe.to_iodata() |> to_string()
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
  end
end
