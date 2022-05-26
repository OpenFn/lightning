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

      assert html =~ "Listing Credentials"

      assert html =~
               credential.body |> Phoenix.HTML.Safe.to_iodata() |> to_string()
    end

    test "saves new credential", %{conn: conn, project: project} do
      {:ok, index_live, _html} =
        live(conn, Routes.credential_index_path(conn, :index))

      assert index_live |> element("a", "New Credential") |> render_click() =~
               "New Credential"

      assert_patch(index_live, Routes.credential_index_path(conn, :new))

      assert index_live
             |> form("#credential-form", credential: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert index_live
             |> form("#credential-form", credential: @create_attrs)
             |> render_change()

      index_live
      |> element("#project_list")
      |> render_hook("select_item", %{"id" => project.id})

      index_live
      |> element("button", "Add")
      |> render_click()

      index_live
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

  describe "Show" do
    setup [:create_credential]

    test "displays credential", %{conn: conn, credential: credential} do
      {:ok, _show_live, html} =
        live(conn, Routes.credential_show_path(conn, :show, credential))

      assert html =~ "Show Credential"
      assert html =~ credential.name
    end

    test "can't display others credentials", %{
      conn: conn,
      credential: _credential
    } do
      assert live(
               conn,
               Routes.credential_show_path(
                 conn,
                 :show,
                 Lightning.CredentialsFixtures.credential_fixture()
               )
             ) ==
               {:error,
                {:live_redirect,
                 %{
                   flash: %{"error" => "You can't access that page"},
                   to: "/credentials"
                 }}}
    end
  end
end
