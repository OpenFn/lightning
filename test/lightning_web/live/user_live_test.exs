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

    test "updates user as support user", %{conn: conn} do
      user = user_fixture()

      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      {:ok, form_live, _} =
        index_live
        |> element("#user-#{user.id} a", "Edit")
        |> render_click()
        |> follow_redirect(conn, Routes.user_edit_path(conn, :edit, user))

      assert %{support_user: false} = user

      refute has_element?(form_live, "#heads-up-description")

      refute has_element?(
               form_live,
               "input[type='checkbox'][name='user[support_user]'][checked]"
             )

      assert form_live
             |> element("input[type='checkbox'][phx-click='support_heads_up']")
             |> render_click() =~
               "This user will be able to access ALL projects that have support access enabled"

      assert has_element?(form_live, "#heads-up-description")

      assert has_element?(
               form_live,
               "input[type='checkbox'][name='user[support_user]'][value='true']"
             )

      {:ok, _, html} =
        form_live
        |> form("#user-form", user: %{support_user: true})
        |> render_submit()
        |> follow_redirect(conn, Routes.user_index_path(conn, :index))

      assert html =~ "User updated successfully"

      assert %{support_user: true} = Repo.reload!(user)
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

      formated_deletion_date =
        DateTime.utc_now() |> Timex.shift(days: 7) |> Calendar.strftime("%d %b")

      refute html =~ formated_deletion_date

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

      assert html =~ formated_deletion_date
    end

    test "disables the delete link for listed superusers", %{
      conn: conn,
      user: user
    } do
      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      assert(
        index_live
        |> has_element?(
          "span#delete-#{user.id}.cursor-not-allowed",
          "Delete"
        )
      )

      refute(
        index_live
        |> has_element?("a#delete-#{user.id}", "Delete")
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
               "a#cancel-deletion-#{user.id}",
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
          "span#delete-now-#{user.id}.cursor-not-allowed",
          "Delete now"
        )
      )

      refute(
        index_live
        |> has_element?(
          "a#delete-now-#{user.id}",
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

    test "sorting by email column works correctly", %{conn: conn} do
      _user_a = user_fixture(email: "alpha@example.com", first_name: "Alpha")
      _user_b = user_fixture(email: "beta@example.com", first_name: "Beta")
      _user_c = user_fixture(email: "charlie@example.com", first_name: "Charlie")

      {:ok, index_live, html} = live(conn, Routes.user_index_path(conn, :index))

      # Check initial state (should be sorted by email ascending by default)
      assert assert_elements_in_order(html, [
               "alpha@example.com",
               "beta@example.com",
               "charlie@example.com"
             ])

      # Click email header to toggle to descending
      index_live
      |> element("a[phx-click='sort'][phx-value-by='email']")
      |> render_click()

      html = render(index_live)

      # Check reverse order
      assert assert_elements_in_order(html, [
               "charlie@example.com",
               "beta@example.com",
               "alpha@example.com"
             ])
    end

    test "sorting by first name column works correctly", %{conn: conn} do
      _user_a = user_fixture(first_name: "Alice", email: "alice@example.com")
      _user_b = user_fixture(first_name: "Bob", email: "bob@example.com")
      _user_c = user_fixture(first_name: "Charlie", email: "charlie@example.com")

      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      # Click first name header to sort ascending
      index_live
      |> element("a[phx-click='sort'][phx-value-by='first_name']")
      |> render_click()

      html = render(index_live)

      # Check that first names are in alphabetical order
      assert assert_elements_in_order(html, ["Alice", "Bob", "Charlie"])
    end

    test "sorting by role column works correctly", %{conn: conn} do
      _user_a = user_fixture(role: :user, email: "user@example.com")
      _user_b = user_fixture(role: :superuser, email: "super@example.com")

      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      # Click role header to sort
      index_live
      |> element("a[phx-click='sort'][phx-value-by='role']")
      |> render_click()

      html = render(index_live)

      # Check that superuser appears before user (alphabetical order)
      assert assert_elements_in_order(html, ["superuser", "user@example.com"])
    end

    test "sorting by enabled status works correctly", %{conn: conn} do
      _user_enabled = user_fixture(disabled: false, email: "enabled@example.com")

      _user_disabled =
        user_fixture(disabled: true, email: "disabled@example.com")

      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      # Click enabled header to sort (enabled users should appear first)
      index_live
      |> element("a[phx-click='sort'][phx-value-by='enabled']")
      |> render_click()

      html = render(index_live)

      # Check that disabled user appears before enabled user (false < true)
      assert assert_elements_in_order(html, [
               "disabled@example.com",
               "enabled@example.com"
             ])
    end

    test "filtering users by search term works correctly", %{conn: conn} do
      _user_a =
        user_fixture(
          first_name: "Alice",
          last_name: "Smith",
          email: "alice@example.com",
          role: :user
        )

      _user_b =
        user_fixture(
          first_name: "Bob",
          last_name: "Johnson",
          email: "bob@example.com",
          role: :superuser
        )

      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      # Filter by first name
      index_live
      |> element("input[name=filter]")
      |> render_keyup(%{"key" => "a", "value" => "alice"})

      html = render(index_live)
      assert html =~ "alice@example.com"
      refute html =~ "bob@example.com"

      # Filter by role
      index_live
      |> element("input[name=filter]")
      |> render_keyup(%{"key" => "s", "value" => "superuser"})

      html = render(index_live)
      assert html =~ "bob@example.com"
      refute html =~ "alice@example.com"

      # Clear filter
      index_live
      |> element("#clear_filter_button")
      |> render_click()

      html = render(index_live)
      assert html =~ "alice@example.com"
      assert html =~ "bob@example.com"
    end

    test "filter input shows clear button when text is entered", %{conn: conn} do
      {:ok, index_live, _html} = live(conn, Routes.user_index_path(conn, :index))

      # Initially clear button should be hidden
      assert has_element?(index_live, "#clear_filter_button.hidden")

      # Type in filter
      index_live
      |> element("input[name=filter]")
      |> render_keyup(%{"key" => "a", "value" => "test"})

      # Clear button should now be visible (no longer hidden)
      refute has_element?(index_live, "#clear_filter_button.hidden")
      assert has_element?(index_live, "a[phx-click='clear_filter']")
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

  # Helper to check element order in rendered HTML using proper parsing
  defp assert_elements_in_order(
         html,
         elements,
         table_selector \\ "table tbody tr"
       ) do
    parsed_html = Floki.parse_fragment!(html)
    rows = Floki.find(parsed_html, table_selector)

    row_texts = Enum.map(rows, fn row -> Floki.text(row) end)

    # Find positions of each element in the row texts
    positions =
      Enum.map(elements, fn element ->
        Enum.find_index(row_texts, fn row_text ->
          String.contains?(row_text, element)
        end)
      end)

    # Check if positions are in ascending order
    positions == Enum.sort(positions)
  end
end
