defmodule LightningWeb.AccountsConfirmationLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  setup do
    Mox.stub(Lightning.MockConfig, :check_flag?, fn
      :require_email_verification -> true
      flag -> Lightning.Config.API.check_flag?(flag)
    end)

    :ok
  end

  test "Users who have their accounts confirmed do not see the banner",
       %{conn: conn} do
    user = insert(:user, confirmed_at: DateTime.utc_now())

    {:ok, view, _html} =
      conn |> log_in_user(user) |> live("/projects", on_error: :raise)

    refute view |> has_element?("#account-confirmation-alert")
  end

  test "Users who have their account not confirmed but created them within 48 hours see the confirmation banner and a working application",
       %{conn: conn} do
    user = insert(:user, confirmed_at: nil, inserted_at: DateTime.utc_now())

    {:ok, view, html} =
      conn |> log_in_user(user) |> live("/projects", on_error: :raise)

    assert view |> has_element?("#account-confirmation-alert")
    assert html =~ "Please confirm your account before"

    # The page itself still renders for a user inside the grace period — the
    # banner warns, it does not block.
    assert view |> has_element?("#user-projects-section")
  end

  test "Users who have their account not confirmed but created them within 48 hours dont see the banner if email verification isn't enabled",
       %{conn: conn} do
    Mox.stub(
      Lightning.MockConfig,
      :check_flag?,
      fn
        :require_email_verification -> false
        flag -> Lightning.Config.API.check_flag?(flag)
      end
    )

    user = insert(:user, confirmed_at: nil, inserted_at: DateTime.utc_now())

    {:ok, view, _html} =
      conn |> log_in_user(user) |> live("/projects", on_error: :raise)

    refute view |> has_element?("#account-confirmation-alert")
  end

  test "Users who have their account not confirmed and created them after 48 hours are sent to the confirmation-required page",
       %{conn: conn} do
    user =
      insert(:user,
        confirmed_at: nil,
        inserted_at: DateTime.utc_now() |> Timex.shift(hours: -50)
      )

    conn = log_in_user(conn, user)

    assert {:error, {redirect, %{to: "/users/confirm-required"}}} =
             live(conn, ~p"/projects")

    assert redirect in [:redirect, :live_redirect]
  end

  test "Users who have their account not confirmed but created them after 48 hours dont see the banner when verification is disabled",
       %{conn: conn} do
    Mox.stub(
      Lightning.MockConfig,
      :check_flag?,
      fn
        :require_email_verification -> false
        flag -> Lightning.Config.API.check_flag?(flag)
      end
    )

    user =
      insert(:user,
        confirmed_at: nil,
        inserted_at: DateTime.utc_now() |> Timex.shift(hours: -50)
      )

    {:ok, view, _html} =
      conn |> log_in_user(user) |> live("/projects", on_error: :raise)

    refute view |> has_element?("#account-confirmation-alert")
  end
end
