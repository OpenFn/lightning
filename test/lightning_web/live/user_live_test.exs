defmodule LightningWeb.UserLiveTest do
  use LightningWeb.ConnCase, async: true

  alias Lightning.Accounts.User
  alias Lightning.AccountsFixtures

  import Lightning.AccountsFixtures
  import Lightning.Factories
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  @create_attrs %{
    email: "test@example.com",
    first_name: "some first_name",
    last_name: "some last_name",
    password: "some password",
    role: "user"
  }
  @update_attrs %{
    email: "test-updated@example.com",
    first_name: "some updated first_name",
    last_name: "some updated last_name",
    password: "some updated password",
    role: :superuser,
    disabled: true
  }
  @invalid_attrs %{email: nil, first_name: nil, last_name: nil, password: nil}

  @invalid_schedule_deletion_attrs %{
    "scheduled_deletion_email" => "invalid@email.com"
  }

  describe "Index for super user" do
    setup :register_and_log_in_superuser

    test "lists all users", %{conn: conn, user: user} do
      {:ok, _index_live, html} = live(conn, Routes.user_index_path(conn, :index))

      assert html =~ "Users"
      assert html =~ user.email
    end

    test "saves new user", %{conn: conn} do
      %{first_name: first_name, last_name: last_name} = @create_attrs

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

      assert %{
               first_name: ^first_name,
               last_name: ^last_name,
               role: :user
             } = Repo.get_by(User, email: @create_attrs.email)
    end

    test "allows creation of a super user", %{conn: conn} do
      %{first_name: first_name, last_name: last_name} = @create_attrs

      superuser_attrs = @create_attrs |> Map.put(:role, "superuser")

      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      {:ok, edit_live, _html} =
        index_live
        |> element("a", "New User")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.user_edit_path(conn, :new)
        )

      {:ok, _, html} =
        edit_live
        |> form("#user-form", user: superuser_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.user_index_path(conn, :index))

      assert html =~ "User created successfully"
      assert html =~ "test@example.com"

      assert %{
               first_name: ^first_name,
               last_name: ^last_name,
               role: :superuser
             } = Repo.get_by(User, email: @create_attrs.email)
    end

    test "updates user in listing", %{conn: conn} do
      user = user_fixture()

      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      {:ok, form_live, _} =
        index_live
        |> element("#user-#{user.id} a", "Edit")
        |> render_click()
        |> follow_redirect(conn, Routes.user_edit_path(conn, :edit, user))

      assert form_live
             |> form("#user-form", user: @invalid_attrs)
             |> render_change() =~ "can&#39;t be blank"

      refute user_attrs_match?(user, @update_attrs)

      {:ok, _, html} =
        form_live
        |> form("#user-form", user: @update_attrs)
        |> render_submit()
        |> follow_redirect(conn, Routes.user_index_path(conn, :index))

      assert html =~ "User updated successfully"

      assert Repo.reload!(user) |> user_attrs_match?(@update_attrs)
    end

    test "provides `Scheduled Deletion` when editing a normal user", %{
      conn: conn
    } do
      user = user_fixture()

      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      {:ok, form_live, _} =
        index_live
        |> element("#user-#{user.id} a", "Edit")
        |> render_click()
        |> follow_redirect(conn, Routes.user_edit_path(conn, :edit, user))

      assert(
        form_live
        |> has_element?("input[name=\"user[scheduled_deletion]\"]")
      )
    end

    test "hides `Scheduled Deletion` when changing to a superuser", %{
      conn: conn
    } do
      user = user_fixture()

      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      {:ok, form_live, _} =
        index_live
        |> element("#user-#{user.id} a", "Edit")
        |> render_click()
        |> follow_redirect(conn, Routes.user_edit_path(conn, :edit, user))

      form_live
      |> element("#user-form")
      |> render_change(%{"user" => %{"role" => "superuser"}})

      refute(
        form_live
        |> has_element?("input[name=\"user[scheduled_deletion]\"]")
      )
    end

    test "does not show `Scheduled Deletion` field when editing superuser", %{
      conn: conn,
      user: user
    } do
      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      {:ok, form_live, _} =
        index_live
        |> element("#user-#{user.id} a", "Edit")
        |> render_click()
        |> follow_redirect(conn, Routes.user_edit_path(conn, :edit, user))

      refute(
        form_live
        |> has_element?("input[name=\"user[scheduled_deletion]\"]")
      )
    end

    test "shows `Scheduled Deletion` field when changing to user", %{
      conn: conn,
      user: user
    } do
      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      {:ok, form_live, _} =
        index_live
        |> element("#user-#{user.id} a", "Edit")
        |> render_click()
        |> follow_redirect(conn, Routes.user_edit_path(conn, :edit, user))

      form_live
      |> element("#user-form")
      |> render_change(%{"user" => %{"role" => "user"}})

      assert(
        form_live
        |> has_element?("input[name=\"user[scheduled_deletion]\"]")
      )
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
            "scheduled_deletion_email" => user.email
          }
        )
        |> render_submit()
        |> follow_redirect(conn, Routes.user_index_path(conn, :index))

      assert has_element?(index_live, "#user-#{user.id}")

      assert_email_sent(
        subject: "Your account has been scheduled for deletion",
        to: Swoosh.Email.Recipient.format(user)
      )

      assert html =~
               "#{DateTime.utc_now() |> Timex.shift(days: 7) |> Map.fetch!(:year)}"
    end

    test "disables the delete link for listed superusers", %{
      conn: conn,
      user: user
    } do
      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      assert(
        index_live
        |> has_element?(
          "span#delete-#{user.id}.table-action-disabled",
          "Delete"
        )
      )

      refute(
        index_live
        |> has_element?("a#delete-#{user.id}.table-action", "Delete")
      )
    end

    test "allows superuser to click cancel for closing user deletion modal", %{
      conn: conn
    } do
      user = user_fixture()

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
             |> render_click()

      flash = assert_redirected(index_live, ~p"/settings/users")

      assert flash["info"] == "User deletion canceled"
    end

    test "retains a cancel deletion button for superusers pending deletion", %{
      conn: conn,
      user: user
    } do
      user
      |> Ecto.Changeset.change(%{scheduled_deletion: ~U[2024-12-28 01:02:03Z]})
      |> Repo.update!()

      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      assert index_live
             |> has_element?(
               "a#cancel-deletion-#{user.id}.table-action",
               "Cancel deletion"
             )
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
            "scheduled_deletion_email" => user.email
          }
        )
        |> render_submit()
        |> follow_redirect(conn, Routes.user_index_path(conn, :index))

      assert html =~ "User deleted"

      refute index_live |> element("user-#{user.id}") |> has_element?()
    end

    test "does not enable the `Delete now` button for a superuser", %{
      conn: conn,
      user: user
    } do
      user
      |> Ecto.Changeset.change(%{scheduled_deletion: ~U[2024-12-28 01:02:03Z]})
      |> Repo.update!()

      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      assert(
        index_live
        |> has_element?(
          "span#delete-now-#{user.id}.table-action-disabled",
          "Delete now"
        )
      )

      refute(
        index_live
        |> has_element?(
          "a#delete-now-#{user.id}.table-action",
          "Delete now"
        )
      )
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
        |> follow_redirect(conn, "/projects")

      assert html =~ "Sorry, you don&#39;t have access to that."
    end

    test "a regular user cannot access a user edit page", %{
      conn: conn,
      user: user
    } do
      {:ok, _index_live, html} =
        live(conn, Routes.user_edit_path(conn, :edit, user.id))
        |> follow_redirect(conn, "/projects")

      assert html =~ "Sorry, you don&#39;t have access to that."
    end
  end

  def user_attrs_match?(user, attrs) do
    Enum.all?(attrs, fn
      {:password, password} ->
        Lightning.Accounts.User.valid_password?(user, password)

      {key, value} ->
        Map.get(user, key) == value
    end)
  end
end
