defmodule LightningWeb.UserLiveTest do
  use LightningWeb.ConnCase

  import Phoenix.LiveViewTest
  import Lightning.AccountsFixtures

  @create_attrs %{
    email: "test@example.com",
    first_name: "some first_name",
    last_name: "some last_name",
    password: "some password"
  }
  @update_attrs %{
    email: "test-updated@example.com",
    first_name: "some updated first_name",
    last_name: "some updated last_name",
    password: "some updated password"
  }
  @invalid_attrs %{email: nil, first_name: nil, last_name: nil, password: nil}

  defp create_user(_) do
    user = user_fixture()
    %{user: user}
  end

  setup :register_and_log_in_user

  describe "Index" do
    setup [:create_user]

    test "lists all users", %{conn: conn, user: user} do
      {:ok, _index_live, html} = live(conn, Routes.user_index_path(conn, :index))

      assert html =~ "Listing Users"
      assert html =~ user.email
    end

    test "saves new user", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      assert index_live |> element("a", "New User") |> render_click() =~
               "New User"

      assert_patch(index_live, Routes.user_index_path(conn, :new))

      assert index_live
             |> form("#user-form", user: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        index_live
        |> form("#user-form", user: @create_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.user_index_path(conn, :index))

      assert html =~ "User created successfully"
      assert html =~ "test@example.com"
    end

    test "updates user in listing", %{conn: conn, user: user} do
      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      {:ok, form_live, _} =
        index_live
        |> element("#user-#{user.id} a", "Edit")
        |> render_click()
        |> follow_redirect(conn, Routes.user_edit_path(conn, :edit, user))

      assert form_live
             |> form("#user-form", user: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        form_live
        |> form("#user-form", user: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.user_index_path(conn, :index))

      assert html =~ "User updated successfully"
    end

    test "deletes user in listing", %{conn: conn, user: user} do
      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      assert index_live
             |> element("#user-#{user.id} a", "Delete")
             |> render_click()

      refute has_element?(index_live, "#user-#{user.id}")
    end
  end
end
