defmodule LightningWeb.UserConfirmationRequiredLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories
  import Lightning.AccountsFixtures, only: [extract_token_from_email: 1]
  import Swoosh.TestAssertions

  alias Lightning.Accounts

  # The page is drawn by React from data-props (the address). Its copy, the
  # alert each answer shows, the form's own checks and the field errors are
  # tested in the design system's AuthConfirmationRequiredPage.test.tsx; the
  # events the island sends in assets/test/design-system/. These tests cover
  # the gate and what the server answers.
  @page "#auth-confirmation-required-page"

  @password "hello world!"

  setup do
    Mox.stub(Lightning.MockConfig, :check_flag?, fn
      :require_email_verification -> true
      flag -> Lightning.Config.API.check_flag?(flag)
    end)

    :ok
  end

  defp locked_out_user(_context) do
    %{
      user:
        insert(:user,
          confirmed_at: nil,
          inserted_at: DateTime.utc_now() |> Timex.shift(hours: -50)
        )
    }
  end

  defp resend(view),
    do: push_page_event(view, @page, "resend_confirmation_email")

  defp change_email(view, email, password),
    do:
      push_page_event(view, @page, "change_email", %{
        "email" => email,
        "currentPassword" => password
      })

  describe "a locked-out account" do
    setup [:locked_out_user]

    test "sees the block explained for their address", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} =
        conn |> log_in_user(user) |> live(~p"/users/confirm-required")

      assert page_title(view) =~ "Confirm your email"
      assert page_props(view, @page) == %{"email" => user.email}
    end

    test "gets no chrome, and no project inventory, on the landing page",
         %{conn: conn, user: user} do
      project = insert(:project, project_users: [%{user: user, role: :owner}])

      {:ok, _view, html} =
        conn |> log_in_user(user) |> live(~p"/users/confirm-required")

      refute html =~ "global-project-picker"
      refute html =~ project.name
      refute html =~ "side-menu"
      refute html =~ "user-menu-trigger"
      refute html =~ "account-confirmation-modal"
    end

    test "can resend the confirmation email and is told it was sent", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} =
        conn |> log_in_user(user) |> live(~p"/users/confirm-required")

      resend(view)
      assert_reply(view, %{status: "sent"})

      assert_email_sent(
        subject: "Confirm your OpenFn account",
        to: user.email
      )
    end

    test "is rate-limited to three resends in the window, and told so", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} =
        conn |> log_in_user(user) |> live(~p"/users/confirm-required")

      for _ <- 1..3 do
        resend(view)
        assert_reply(view, %{status: "sent"})
      end

      resend(view)
      assert_reply(view, %{status: "throttled", message: message})
      assert message =~ "you can request another in a few minutes"

      for _ <- 1..3 do
        assert_email_sent(subject: "Confirm your OpenFn account", to: user.email)
      end

      refute_email_sent(subject: "Confirm your OpenFn account")
    end

    test "cannot spend that window on /users/send-confirmation-email instead", %{
      conn: conn,
      user: user
    } do
      conn = log_in_user(conn, user)

      for _ <- 1..3 do
        assert conn
               |> get(~p"/users/send-confirmation-email")
               |> redirected_to() == "/projects"
      end

      for _ <- 1..3 do
        assert_email_sent(subject: "Confirm your OpenFn account", to: user.email)
      end

      {:ok, view, _html} = live(conn, ~p"/users/confirm-required")

      resend(view)
      assert_reply(view, %{status: "throttled"})
      refute_email_sent(subject: "Confirm your OpenFn account")
    end
  end

  describe "correcting a mistyped address" do
    setup [:locked_out_user]

    test "is refused without the current password", %{conn: conn, user: user} do
      {:ok, view, _html} =
        conn |> log_in_user(user) |> live(~p"/users/confirm-required")

      change_email(view, "typo-fixed@example.com", "wrong")

      assert_reply(view, %{
        fieldErrors: %{"currentPassword" => ["Your passwords do not match."]}
      })

      refute_email_sent(subject: "Please confirm your new email")
    end

    test "is refused with the same, a malformed or a missing address", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} =
        conn |> log_in_user(user) |> live(~p"/users/confirm-required")

      change_email(view, user.email, @password)
      assert_reply(view, %{fieldErrors: %{"email" => messages}})
      assert Enum.any?(messages, &(&1 =~ "change your email"))

      change_email(view, "not an email", @password)
      assert_reply(view, %{fieldErrors: %{"email" => [_]}})

      taken = insert(:user).email
      change_email(view, taken, @password)
      assert_reply(view, %{fieldErrors: %{"email" => [unique]}})
      assert unique =~ "unique"

      # Crafted payloads: non-string fields read as blank, a non-map is refused.
      change_email(view, %{"$" => 1}, ["x"])

      assert_reply(view, %{
        fieldErrors: %{"email" => [_], "currentPassword" => [_]}
      })

      push_page_event(view, @page, "change_email", ["x"])
      assert_reply(view, %{error: "Invalid request"})

      refute_email_sent(subject: "Please confirm your new email")
    end

    test "sends instructions to the new address", %{conn: conn, user: user} do
      {:ok, view, _html} =
        conn |> log_in_user(user) |> live(~p"/users/confirm-required")

      change_email(view, "typo-fixed@example.com", @password)

      # The password typed to authorise the change is not echoed.
      assert_reply(
        view,
        %{status: "requested", email: "typo-fixed@example.com"} = reply
      )

      refute inspect(reply) =~ @password

      # request_email_update/2 warns the old address before instructing the new
      # one; Swoosh asserts in order.
      assert_email_sent(subject: "Your OpenFn email was changed")

      assert_email_sent(fn email ->
        assert email.subject == "Please confirm your new email"
        assert [{_name, "typo-fixed@example.com"}] = email.to
      end)
    end

    test "lifts the lockout once the emailed link is opened",
         %{conn: conn, user: user} do
      conn = log_in_user(conn, user)

      {:ok, view, _html} = live(conn, ~p"/users/confirm-required")

      change_email(view, "typo-fixed@example.com", @password)
      assert_reply(view, %{status: "requested"})

      assert_email_sent(subject: "Your OpenFn email was changed")

      assert_email_sent(fn email ->
        assert email.subject == "Please confirm your new email"
        token = extract_token_from_email(email)

        assert conn
               |> get(~p"/profile/confirm_email/#{token}")
               |> redirected_to() ==
                 "/projects"
      end)

      confirmed = Repo.reload(user)

      assert confirmed.email == "typo-fixed@example.com"
      assert confirmed.confirmed_at
      refute Accounts.locked_out?(confirmed)
    end

    test "is throttled after three corrections, and told so",
         %{conn: conn, user: user} do
      {:ok, view, _html} =
        conn |> log_in_user(user) |> live(~p"/users/confirm-required")

      for n <- 1..3 do
        change_email(view, "typo-fixed-#{n}@example.com", @password)
        assert_reply(view, %{status: "requested"})
      end

      change_email(view, "typo-fixed-4@example.com", @password)
      assert_reply(view, %{status: "throttled"})

      for _ <- 1..3 do
        assert_email_sent(subject: "Your OpenFn email was changed")
        assert_email_sent(subject: "Please confirm your new email")
      end

      refute_email_sent(subject: "Please confirm your new email")
    end

    test "still works once the resend allowance is spent", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} =
        conn |> log_in_user(user) |> live(~p"/users/confirm-required")

      for _ <- 1..4 do
        resend(view)
        assert_reply(view, %{status: _})
      end

      for _ <- 1..3 do
        assert_email_sent(subject: "Confirm your OpenFn account", to: user.email)
      end

      change_email(view, "typo-fixed@example.com", @password)
      assert_reply(view, %{status: "requested"})

      assert_email_sent(subject: "Your OpenFn email was changed")
      assert_email_sent(subject: "Please confirm your new email")
    end
  end

  describe "an account that is not locked out" do
    test "is redirected away once confirmed", %{conn: conn} do
      user = insert(:user, confirmed_at: DateTime.utc_now())

      assert {:error, {:redirect, %{to: "/projects"}}} =
               conn |> log_in_user(user) |> live(~p"/users/confirm-required")
    end

    test "is redirected away while inside the 48-hour grace period", %{
      conn: conn
    } do
      user = insert(:user, confirmed_at: nil, inserted_at: DateTime.utc_now())

      assert {:error, {:redirect, %{to: "/projects"}}} =
               conn |> log_in_user(user) |> live(~p"/users/confirm-required")
    end
  end
end
