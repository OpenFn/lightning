defmodule LightningWeb.UserConfirmationRequiredLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories
  import Lightning.AccountsFixtures, only: [extract_token_from_email: 1]
  import Swoosh.TestAssertions

  alias Lightning.Accounts

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

  describe "a locked-out account" do
    setup [:locked_out_user]

    test "sees the block explained and every way out", %{
      conn: conn,
      user: user
    } do
      {:ok, view, html} =
        conn |> log_in_user(user) |> live(~p"/users/confirm-required")

      assert html =~ "Confirm your email address"
      assert html =~ "blocked pending email confirmation"
      assert html =~ user.email

      assert has_element?(view, "#resend-confirmation-email-button")
      assert has_element?(view, "#email-form")
      assert has_element?(view, ~s{a[href="/users/log_out"]})
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

      refute has_element?(view, "#confirmation-email-sent")

      html =
        view |> element("#resend-confirmation-email-button") |> render_click()

      assert html =~ "We have sent a new confirmation link to #{user.email}"

      # Not disabled on success: mail goes astray, and the rate limit is what
      # bounds resends.
      refute has_element?(view, "#resend-confirmation-email-button[disabled]")

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
        view |> element("#resend-confirmation-email-button") |> render_click()
      end

      html =
        view |> element("#resend-confirmation-email-button") |> render_click()

      for _ <- 1..3 do
        assert_email_sent(subject: "Confirm your OpenFn account", to: user.email)
      end

      refute_email_sent(subject: "Confirm your OpenFn account")

      assert html =~ "you can request another in a few minutes"
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

      html =
        view |> element("#resend-confirmation-email-button") |> render_click()

      refute_email_sent(subject: "Confirm your OpenFn account")

      assert html =~ "you can request another in a few minutes"
      refute html =~ "We have sent a new confirmation link"
      refute has_element?(view, "#resend-confirmation-email-button[disabled]")
    end
  end

  describe "correcting a mistyped address" do
    setup [:locked_out_user]

    test "is refused without the current password", %{conn: conn, user: user} do
      {:ok, view, _html} =
        conn |> log_in_user(user) |> live(~p"/users/confirm-required")

      html =
        view
        |> form("#email-form",
          user: %{email: "typo-fixed@example.com", current_password: "wrong"}
        )
        |> render_submit()

      assert html =~ "Your passwords do not match."
      refute html =~ "We have sent confirmation instructions"
      refute_email_sent(subject: "Please confirm your new email")
    end

    test "sends instructions to the new address", %{conn: conn, user: user} do
      {:ok, view, _html} =
        conn |> log_in_user(user) |> live(~p"/users/confirm-required")

      html =
        view
        |> form("#email-form",
          user: %{email: "typo-fixed@example.com", current_password: @password}
        )
        |> render_submit()

      assert html =~
               "We have sent confirmation instructions to typo-fixed@example.com"

      # The password typed to authorise the change is not retained.
      refute html =~ @password

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

      view
      |> form("#email-form",
        user: %{email: "typo-fixed@example.com", current_password: @password}
      )
      |> render_submit()

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

    test "is throttled after three corrections, and told so without losing the address",
         %{conn: conn, user: user} do
      {:ok, view, _html} =
        conn |> log_in_user(user) |> live(~p"/users/confirm-required")

      submit = fn address ->
        view
        |> form("#email-form",
          user: %{email: address, current_password: @password}
        )
        |> render_submit()
      end

      for n <- 1..3, do: submit.("typo-fixed-#{n}@example.com")

      html = submit.("typo-fixed-4@example.com")

      assert html =~ "asked us to change this address a few times recently"
      assert has_element?(view, "#email-change-throttled")

      # Nothing was sent, so the page must not say otherwise, and the address
      # they typed must survive the refusal.
      refute html =~ "We have sent confirmation instructions"
      assert html =~ "typo-fixed-4@example.com"

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
        view |> element("#resend-confirmation-email-button") |> render_click()
      end

      for _ <- 1..3 do
        assert_email_sent(subject: "Confirm your OpenFn account", to: user.email)
      end

      html =
        view
        |> form("#email-form",
          user: %{email: "typo-fixed@example.com", current_password: @password}
        )
        |> render_submit()

      assert html =~
               "We have sent confirmation instructions to typo-fixed@example.com"

      refute has_element?(view, "#email-change-throttled")

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
