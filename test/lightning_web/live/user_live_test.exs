defmodule LightningWeb.UserLiveTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.AccountsFixtures
  import Lightning.Factories
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Lightning.Accounts.User
  alias Lightning.AccountsFixtures

  # Both pages are drawn by React from data-props. What they render from
  # them is tested in the design system: sorting, filtering, the inert
  # delete for superusers, the dialog's copy and email check
  # (AdminUsersPage.test.tsx); the required fields, the support heads-up and
  # the Scheduled Deletion field following the role (AdminUserEditPage.test.tsx).
  # The events the islands send are in assets/test/design-system/.
  @list "#admin-users-page"
  @form "#admin-user-edit-page"

  @create_attrs %{
    "firstName" => "some first_name",
    "lastName" => "some last_name",
    "email" => "test@example.com",
    "password" => "some password",
    "role" => "user",
    "supportUser" => false
  }
  @update_attrs %{
    "firstName" => "some updated first_name",
    "lastName" => "some updated last_name",
    "email" => "test-updated@example.com",
    "password" => "some updated password",
    "role" => "superuser",
    "disabled" => true
  }
  @invalid_attrs %{
    "firstName" => "",
    "lastName" => "",
    "email" => "",
    "password" => ""
  }

  defp rows(view), do: page_props(view, @list)["users"]
  defp row(view, user), do: Enum.find(rows(view), &(&1["id"] == user.id))

  # The page sends every field it holds; the test fills them from the account.
  defp form_attrs(%User{} = user, changes) do
    Map.merge(
      %{
        "firstName" => user.first_name,
        "lastName" => user.last_name,
        "email" => user.email,
        "password" => "",
        "role" => to_string(user.role),
        "supportUser" => user.support_user,
        "scheduledDeletion" => "",
        "disabled" => user.disabled
      },
      changes
    )
  end

  defp save(view, attrs), do: push_page_event(view, @form, "save_user", attrs)

  defp delete_user(view, email),
    do: push_page_event(view, @list, "delete_user", %{"email" => email})

  defp cancel_deletion(view, id),
    do: push_page_event(view, @list, "cancel_deletion", %{"id" => id})

  describe "Index for super user" do
    setup :register_and_log_in_superuser

    test "lists all users", %{conn: conn, user: user} do
      {:ok, view, html} = live(conn, ~p"/settings/users")

      assert html =~ "Users"

      assert %{
               "email" => email,
               "firstName" => first_name,
               "role" => "superuser",
               "disabled" => false,
               "supportUser" => false,
               "scheduledDeletion" => nil
             } = row(view, user)

      assert email == user.email
      assert first_name == user.first_name
      assert page_props(view, @list)["deleteUser"] == nil
    end

    test "saves new user", %{conn: conn} do
      %{"firstName" => first_name, "lastName" => last_name} = @create_attrs

      {:ok, view, _html} = live(conn, ~p"/settings/users/new")

      assert page_props(view, @form) == %{"user" => nil}

      save(view, @invalid_attrs)

      assert_reply(view, %{fieldErrors: errors})
      assert_blank(errors, ~w(firstName lastName email password))

      {:ok, view, html} =
        view
        |> save(@create_attrs)
        |> follow_redirect(conn, ~p"/settings/users")

      assert html =~ "User created successfully"
      assert Enum.any?(rows(view), &(&1["email"] == "test@example.com"))

      assert %{
               first_name: ^first_name,
               last_name: ^last_name,
               role: :user
             } = Repo.get_by(User, email: @create_attrs["email"])

      assert_email_sent(
        subject: "Confirm your OpenFn account",
        to: {"#{first_name} #{last_name}", "test@example.com"}
      )
    end

    test "allows creation of a super user", %{conn: conn} do
      %{"firstName" => first_name, "lastName" => last_name} = @create_attrs

      {:ok, view, _html} = live(conn, ~p"/settings/users/new")

      {:ok, view, html} =
        view
        |> save(
          Map.merge(@create_attrs, %{
            "role" => "superuser",
            # The new-user form never showed these; a payload with them is ignored.
            "disabled" => true,
            "scheduledDeletion" => "2030-01-01T00:00:00Z"
          })
        )
        |> follow_redirect(conn, ~p"/settings/users")

      assert html =~ "User created successfully"
      assert Enum.any?(rows(view), &(&1["email"] == "test@example.com"))

      assert %{
               first_name: ^first_name,
               last_name: ^last_name,
               role: :superuser,
               disabled: false,
               scheduled_deletion: nil
             } = Repo.get_by(User, email: @create_attrs["email"])
    end

    test "refuses a new user with a taken email or a short password", %{
      conn: conn,
      user: superuser
    } do
      {:ok, view, _html} = live(conn, ~p"/settings/users/new")

      save(
        view,
        Map.merge(@create_attrs, %{
          "email" => superuser.email,
          "password" => "short"
        })
      )

      assert_reply(view, %{
        fieldErrors: %{"email" => [email], "password" => [password]}
      })

      assert email =~ "should be unique"
      assert password =~ "12"
      refute Repo.get_by(User, email: "test@example.com")
    end

    test "updates user in listing", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/settings/users/#{user.id}")

      assert %{"user" => %{"id" => id, "email" => email}} =
               page_props(view, @form)

      assert id == user.id
      assert email == user.email

      save(view, form_attrs(user, @invalid_attrs))

      assert_reply(view, %{fieldErrors: errors})
      assert_blank(errors, ~w(firstName lastName email))

      refute user_attrs_match?(user, @update_attrs)

      {:ok, _view, html} =
        view
        |> save(form_attrs(user, @update_attrs))
        |> follow_redirect(conn, ~p"/settings/users")

      assert html =~ "User updated successfully"

      assert Repo.reload!(user) |> user_attrs_match?(@update_attrs)
    end

    test "leaves the password alone when the form sends it empty", %{
      conn: conn
    } do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/settings/users/#{user.id}")

      assert {:error, {:live_redirect, _}} =
               save(view, form_attrs(user, %{"lastName" => "Okafor-Bello"}))

      reloaded = Repo.reload!(user)
      assert reloaded.last_name == "Okafor-Bello"
      assert User.valid_password?(reloaded, valid_user_password())
    end

    test "records the superuser behind a create, a change and a disable, but not a save that changes nothing",
         %{conn: conn, user: superuser} do
      {:ok, new_live, _html} = live(conn, ~p"/settings/users/new")

      assert {:error, {:live_redirect, _}} = save(new_live, @create_attrs)

      created = Repo.get_by!(User, email: @create_attrs["email"])

      for changes <- [
            %{"firstName" => "Renamed"},
            %{"disabled" => true},
            %{"firstName" => "Renamed"}
          ] do
        {:ok, edit_live, _html} = live(conn, ~p"/settings/users/#{created.id}")

        assert {:error, {:live_redirect, _}} =
                 save(edit_live, form_attrs(Repo.reload!(created), changes))
      end

      %{entries: audits} = Lightning.Auditing.list_all()

      assert Enum.all?(
               audits,
               &({&1.actor_type, &1.actor_id, &1.item_id} ==
                   {:user, superuser.id, created.id})
             )

      assert audits |> Enum.map(&{&1.event, &1.changes.before}) |> Enum.sort() ==
               [
                 {"created", nil},
                 {"updated", %{"disabled" => false}},
                 {"updated", %{"first_name" => "some first_name"}}
               ]
    end

    test "updates user as support user", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/settings/users/#{user.id}")

      assert %{"user" => %{"supportUser" => false}} = page_props(view, @form)

      {:ok, _view, html} =
        view
        |> save(form_attrs(user, %{"supportUser" => true}))
        |> follow_redirect(conn, ~p"/settings/users")

      assert html =~ "User updated successfully"

      assert %{support_user: true} = Repo.reload!(user)
    end

    test "clears a scheduled deletion when the role becomes superuser", %{
      conn: conn
    } do
      user =
        user_fixture(scheduled_deletion: Timex.now() |> Timex.shift(days: 7))

      {:ok, view, _html} = live(conn, ~p"/settings/users/#{user.id}")

      assert {:error, {:live_redirect, _}} =
               save(view, form_attrs(user, %{"role" => "superuser"}))

      assert %{role: :superuser, scheduled_deletion: nil} = Repo.reload!(user)
    end

    test "sets a scheduled deletion typed into the form", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/settings/users/#{user.id}")

      assert {:error, {:live_redirect, _}} =
               save(
                 view,
                 form_attrs(user, %{
                   "scheduledDeletion" => "2030-01-02T03:04:05Z"
                 })
               )

      assert %{scheduled_deletion: ~U[2030-01-02 03:04:05Z]} =
               Repo.reload!(user)
    end

    test "refuses a crafted save payload instead of raising", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/settings/users/#{user.id}")

      # Non-string values and unknown keys are ignored, so nothing changes:
      # a save that changes nothing succeeds, as it always has.
      assert {:error, {:live_redirect, _}} =
               save(view, %{
                 "firstName" => %{"$" => 1},
                 "lastName" => ["x"],
                 "email" => 42,
                 "disabled" => "true",
                 "confirmed" => false
               })

      reloaded = Repo.reload!(user)
      assert reloaded.first_name == user.first_name
      assert reloaded.confirmed_at == user.confirmed_at
      refute reloaded.disabled
    end

    test "sends the list back when the account to edit does not exist", %{
      conn: conn
    } do
      for id <- [Ecto.UUID.generate(), "not-a-uuid"] do
        assert {:error, {:live_redirect, %{to: "/settings/users", flash: flash}}} =
                 live(conn, "/settings/users/#{id}")

        assert flash["error"] == "User not found"
      end
    end

    test "allows a superuser to schedule users for deletion in the users list",
         %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/settings/users/#{user.id}/delete")

      assert %{
               "id" => id,
               "email" => email,
               "scheduledDeletion" => nil,
               "hasActivityInProjects" => false
             } = page_props(view, @list)["deleteUser"]

      assert id == user.id
      assert email == user.email
      assert row(view, user)

      delete_user(view, "invalid@email.com")

      assert_reply(view, %{
        error: "This email doesn't match your current email"
      })

      {:ok, view, html} =
        view
        |> delete_user(user.email)
        |> follow_redirect(conn, ~p"/settings/users")

      assert html =~ "User scheduled for deletion"

      assert_email_sent(
        subject: "Your account has been scheduled for deletion",
        to: Swoosh.Email.Recipient.format(user)
      )

      assert %{"scheduledDeletion" => scheduled, "disabled" => true} =
               row(view, user)

      {:ok, scheduled, _offset} = DateTime.from_iso8601(scheduled)
      assert DateTime.diff(scheduled, DateTime.utc_now(), :day) in 6..7
    end

    test "refuses to schedule a superuser opened by URL", %{
      conn: conn,
      user: superuser
    } do
      {:ok, view, _html} =
        live(conn, ~p"/settings/users/#{superuser.id}/delete")

      delete_user(view, superuser.email)

      assert_reply(view, %{error: "You can't delete a superuser account."})
      assert Repo.reload!(superuser).scheduled_deletion == nil
    end

    test "refuses to act when the account's deletion changed since the dialog opened",
         %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/settings/users/#{user.id}/delete")

      # Another admin schedules the account while this dialog shows "Delete".
      user
      |> Ecto.Changeset.change(%{scheduled_deletion: ~U[2030-01-01 00:00:00Z]})
      |> Repo.update!()

      delete_user(view, user.email)

      assert_reply(view, %{
        error:
          "This account's deletion changed since the dialog opened. Reload the page."
      })

      assert Repo.get(User, user.id)
    end

    test "refuses payloads that are not maps instead of raising", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/settings/users/#{user.id}/delete")

      for event <- ["cancel_deletion", "delete_user"] do
        push_page_event(view, @list, event, ["x"])
        assert_reply(view, %{error: "Invalid request"})
      end

      assert Repo.reload!(user).scheduled_deletion == nil
    end

    test "refuses a delete when no dialog is open", %{conn: conn} do
      user = user_fixture()

      {:ok, view, _html} = live(conn, ~p"/settings/users")

      delete_user(view, user.email)

      assert_reply(view, %{error: "User not found"})
      assert Repo.reload!(user).scheduled_deletion == nil
    end

    test "sends the list back when the account to delete does not exist", %{
      conn: conn
    } do
      for id <- [Ecto.UUID.generate(), "not-a-uuid"] do
        assert {:error, {:live_redirect, %{to: "/settings/users", flash: flash}}} =
                 live(conn, "/settings/users/#{id}/delete")

        assert flash["error"] == "User not found"
      end
    end

    test "allows a superuser to cancel scheduled deletion on users", %{
      conn: conn
    } do
      user =
        user_fixture(
          scheduled_deletion: Timex.now() |> Timex.shift(days: 7),
          disabled: true
        )

      {:ok, view, _html} = live(conn, ~p"/settings/users")

      cancel_deletion(view, user.id)

      assert_reply(view, %{})
      assert render(view) =~ "User deletion canceled"

      assert %{"scheduledDeletion" => nil, "disabled" => false} =
               row(view, user)

      assert %{scheduled_deletion: nil, disabled: false} = Repo.reload!(user)
    end

    test "cancels a superuser's pending deletion too", %{conn: conn} do
      superuser = superuser_fixture()

      superuser
      |> Ecto.Changeset.change(%{scheduled_deletion: ~U[2024-12-28 01:02:03Z]})
      |> Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/settings/users")

      assert %{"scheduledDeletion" => "2024-12-28T01:02:03Z"} =
               row(view, superuser)

      cancel_deletion(view, superuser.id)

      assert_reply(view, %{})
      assert Repo.reload!(superuser).scheduled_deletion == nil
    end

    test "refuses to cancel a deletion for an unknown or malformed id", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/settings/users")

      for id <- [Ecto.UUID.generate(), "not-a-uuid", nil, %{"a" => 1}] do
        cancel_deletion(view, id)
        assert_reply(view, %{error: "User not found"})
      end
    end

    test "allows a superuser to perform delete now action on users", %{
      conn: conn
    } do
      user =
        user_fixture(scheduled_deletion: Timex.now() |> Timex.shift(days: 7))

      {:ok, view, _html} = live(conn, ~p"/settings/users/#{user.id}/delete")

      assert %{"scheduledDeletion" => scheduled} =
               page_props(view, @list)["deleteUser"]

      assert scheduled

      {:ok, view, html} =
        view
        |> delete_user(user.email)
        |> follow_redirect(conn, ~p"/settings/users")

      assert html =~ "User deleted"
      refute row(view, user)
      refute Repo.get(User, user.id)
    end

    test "delete now checks the email and the role again", %{conn: conn} do
      user =
        user_fixture(scheduled_deletion: Timex.now() |> Timex.shift(days: 7))

      {:ok, view, _html} = live(conn, ~p"/settings/users/#{user.id}/delete")

      delete_user(view, "someone-else@example.com")
      assert_reply(view, %{error: "This email doesn't match your current email"})

      user |> Ecto.Changeset.change(%{role: :superuser}) |> Repo.update!()

      delete_user(view, user.email)
      assert_reply(view, %{error: "You can't delete a superuser account."})

      assert Repo.get(User, user.id)
    end

    test "delete now shows an error when the user gained runs since the dialog opened",
         %{conn: conn} do
      user =
        user_fixture(scheduled_deletion: Timex.now() |> Timex.shift(days: 7))

      {:ok, view, _html} = live(conn, ~p"/settings/users/#{user.id}/delete")

      assert %{"hasActivityInProjects" => false} =
               page_props(view, @list)["deleteUser"]

      # A run is created after the dialog opens but before the admin
      # confirms; the server checks again rather than trusting the dialog.
      insert_run_for(user)

      {:ok, _view, html} =
        view
        |> delete_user(user.email)
        |> follow_redirect(conn, ~p"/settings/users")

      refute html =~ "User deleted"
      assert html =~ "Cannot delete user that has activities in other projects"
      assert Repo.get(User, user.id), "User should still exist in the database"
    end

    test "cannot delete user that has activities in other projects", %{
      conn: conn
    } do
      user =
        AccountsFixtures.user_fixture(
          scheduled_deletion: Timex.now() |> Timex.shift(days: 7)
        )

      insert_run_for(user)

      {:ok, view, _html} = live(conn, ~p"/settings/users/#{user.id}/delete")

      # The page then shows only why the account cannot be deleted yet.
      assert %{"hasActivityInProjects" => true, "scheduledDeletion" => _} =
               page_props(view, @list)["deleteUser"]
    end
  end

  describe "Index and edit for user" do
    setup :register_and_log_in_user

    test "a regular user cannot access the users list", %{
      conn: conn,
      user: _user
    } do
      {:ok, conn} =
        live(conn, ~p"/settings/users")
        |> follow_redirect(conn, "/projects")

      assert conn.resp_body =~ "Sorry, you don&#39;t have access to that."
    end

    test "a regular user cannot access a user edit page", %{
      conn: conn,
      user: user
    } do
      {:ok, conn} =
        live(conn, ~p"/settings/users/#{user.id}")
        |> follow_redirect(conn, "/projects")

      assert conn.resp_body =~ "Sorry, you don&#39;t have access to that."
    end
  end

  # The changesets word it "This field can't be blank."; the page shows it as is.
  defp assert_blank(errors, fields) do
    for field <- fields do
      assert [message] = errors[field], "no error for #{field}"
      assert message =~ "can't be blank"
    end
  end

  defp insert_run_for(user) do
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
  end

  def user_attrs_match?(user, attrs) do
    Enum.all?(attrs, fn
      {"password", password} ->
        Lightning.Accounts.User.valid_password?(user, password)

      {"firstName", value} ->
        user.first_name == value

      {"lastName", value} ->
        user.last_name == value

      {"role", value} ->
        to_string(user.role) == value

      {key, value} ->
        Map.get(user, String.to_existing_atom(key)) == value
    end)
  end
end
