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
      credential: credential
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

      assert form_live
             |> form("#credential-form",
               credential: Map.put(@update_attrs, :production, true)
             )
             |> render_submit() =~ "some updated body"
    end
  end

  defp submit_disabled(live) do
    live |> has_element?("button[disabled][type=submit]")
  end
end
