defmodule LightningWeb.UserLiveTest do
  alias Lightning.AccountsFixtures
  use LightningWeb.ConnCase, async: true

  import Lightning.{AccountsFixtures}
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions
  import Lightning.Factories

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

    test "allows a superuser to schedule users for deletion in the users list",
         %{
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

      assert_email_sent(
        subject: "Your account has been scheduled for deletion",
        to: user.email
      )

      assert html =~
               "#{DateTime.utc_now() |> Timex.shift(days: 7) |> Map.fetch!(:year)}"
    end

    test "allows superuser to click cancel for closing user deletion modal", %{
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

    test "allows a superuser to cancel scheduled deletion on users", %{
      conn: conn
    } do
      user =
        user_fixture(scheduled_deletion: Timex.now() |> Timex.shift(days: 7))

      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      assert index_live
             |> element("#user-#{user.id} a", "Cancel deletion")
             |> render_click() =~ "User deletion canceled"
    end

    test "allows a superuser to perform delete now action on users", %{
      conn: conn
    } do
      user =
        user_fixture(scheduled_deletion: Timex.now() |> Timex.shift(days: 7))

      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      {:ok, form_live, _html} =
        index_live
        |> element("#user-#{user.id} a", "Delete now")
        |> render_click()
        |> follow_redirect(conn, Routes.user_index_path(conn, :delete, user))

      {:ok, index_live, html} =
        form_live
        |> form("#scheduled_deletion_form",
          user: %{
            scheduled_deletion_email: user.email
          }
        )
        |> render_submit()
        |> follow_redirect(conn, Routes.user_index_path(conn, :index))

      assert html =~ "User deleted"

      refute index_live |> element("user-#{user.id}") |> has_element?()
    end

    test "cannot delete user that has activities in other projects", %{
      conn: conn
    } do
      user =
        AccountsFixtures.user_fixture(
          scheduled_deletion: Timex.now() |> Timex.shift(days: 7)
        )

      workflow = insert(:workflow)
      trigger = insert(:trigger, workflow: workflow)
      dataclip = insert(:dataclip)

      work_order =
        insert(:workorder,
          workflow: workflow,
          trigger: trigger,
          dataclip: dataclip
        )

      insert(:run,
        created_by: user,
        work_order: work_order,
        starting_trigger: trigger,
        dataclip: dataclip
      )

      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      {:ok, _index_live, html} =
        index_live
        |> element("#user-#{user.id} a", "Delete now")
        |> render_click()
        |> follow_redirect(conn, Routes.user_index_path(conn, :delete, user))

      assert html =~
               "This user cannot be deleted until their auditable activities have also been purged."
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

      assert html =~ "Sorry, you don&#39;t have access to that."
    end

    test "a regular user cannot access a user edit page", %{
      conn: conn,
      user: user
    } do
      {:ok, _index_live, html} =
        live(conn, Routes.user_edit_path(conn, :edit, user.id))
        |> follow_redirect(conn, "/")

      assert html =~ "Sorry, you don&#39;t have access to that."
    end
  end
end
