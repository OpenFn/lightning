defmodule LightningWeb.UserLiveTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.{AccountsFixtures}
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

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
    password: "some updated password",
    disabled: true
  }
  @invalid_attrs %{email: nil, first_name: nil, last_name: nil, password: nil}

  @invalid_schedule_deletion_attrs %{
    scheduled_deletion_email: "invalid@email.com"
  }

  describe "Index for super user" do
    setup :register_and_log_in_superuser

    test "lists all users", %{conn: conn, user: user} do
      {:ok, _index_live, html} = live(conn, Routes.user_index_path(conn, :index))

      assert html =~ "Users"
      assert html =~ user.email
    end

    test "saves new user", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      {:ok, edit_live, _html} =
        index_live
        |> element("a", "New User")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.user_edit_path(conn, :new)
        )

      assert edit_live
             |> form("#user-form", user: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      {:ok, _, html} =
        edit_live
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

    test "stops a superuser from deleting themselves", %{
      conn: conn,
      user: user
    } do
      {:ok, index_live, html} = live(conn, Routes.user_index_path(conn, :index))

      assert html =~ "Users"

      refute html =~
               "#{DateTime.utc_now() |> Timex.shift(days: 7) |> Map.fetch!(:year)}"

      {:ok, form_live, _} =
        index_live
        |> element("#user-#{user.id} a", "Delete")
        |> render_click()
        |> follow_redirect(conn, Routes.user_index_path(conn, :delete, user))

      assert form_live
             |> form("#scheduled_deletion_form",
               user: @invalid_schedule_deletion_attrs
             )
             |> render_change() =~
               "This email doesn&#39;t match your current email"

      assert form_live
             |> form("#scheduled_deletion_form",
               user: %{
                 scheduled_deletion_email: user.email
               }
             )
             |> render_submit() =~
               "You can&#39;t delete a superuser account."

      refute_redirected(form_live, Routes.user_index_path(conn, :index))
    end

    test "allows a superuser to delete users in the users list", %{
      conn: conn
    } do
      user = user_fixture()

      {:ok, index_live, html} = live(conn, Routes.user_index_path(conn, :index))

      assert html =~ "Users"

      refute html =~
               "#{DateTime.utc_now() |> Timex.shift(days: 7) |> Map.fetch!(:year)}"

      {:ok, form_live, _} =
        index_live
        |> element("#user-#{user.id} a", "Delete")
        |> render_click()
        |> follow_redirect(conn, Routes.user_index_path(conn, :delete, user))

      assert form_live
             |> form("#scheduled_deletion_form",
               user: @invalid_schedule_deletion_attrs
             )
             |> render_change() =~
               "This email doesn&#39;t match your current email"

      {:ok, index_live, html} =
        form_live
        |> form("#scheduled_deletion_form",
          user: %{
            scheduled_deletion_email: user.email
          }
        )
        |> render_submit()
        |> follow_redirect(conn, Routes.user_index_path(conn, :index))

      assert has_element?(index_live, "#user-#{user.id}")

      assert_email_sent(subject: "Lightning Account Deletion", to: user.email)

      assert html =~
               "#{DateTime.utc_now() |> Timex.shift(days: 7) |> Map.fetch!(:year)}"
    end

    test "superuser cancels deletion", %{
      conn: conn,
      user: user
    } do
      {:ok, index_live, html} = live(conn, Routes.user_index_path(conn, :index))

      assert html =~ "Users"

      {:ok, form_live, _} =
        index_live
        |> element("#user-#{user.id} a", "Delete")
        |> render_click()
        |> follow_redirect(conn, Routes.user_index_path(conn, :delete, user))

      {:ok, index_live, _html} =
        form_live
        |> element("button", "Cancel")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.user_index_path(conn, :index)
        )

      assert has_element?(index_live, "#user-#{user.id}")
    end
  end

  describe "Index and edit for user" do
    setup :register_and_log_in_user

    test "a regular user cannot access the users list", %{
      conn: conn,
      user: _user
    } do
      {:ok, _index_live, html} =
        live(conn, Routes.user_index_path(conn, :index))
        |> follow_redirect(conn, "/")

      assert html =~ "You can&#39;t access that page"
    end

    test "a regular user cannot access a user edit page", %{
      conn: conn,
      user: user
    } do
      {:ok, _index_live, html} =
        live(conn, Routes.user_edit_path(conn, :edit, user.id))
        |> follow_redirect(conn, "/")

      assert html =~ "You can&#39;t access that page"
    end
  end
end
