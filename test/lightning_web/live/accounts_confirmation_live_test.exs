defmodule LightningWeb.AccountsConfirmationLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  setup do
    Mox.stub(
      Lightning.MockConfig,
      :check_flag?,
      fn :require_email_verification -> true end
    )

    :ok
  end

  test "Users who have their accounts confirmed do not see the banner nor the modal in the sessions",
       %{conn: conn} do
    user = insert(:user, confirmed_at: DateTime.utc_now())

    {:ok, view, _html} =
      conn |> log_in_user(user) |> live("/projects", on_error: :raise)

    refute view |> has_element?("#account-confirmation-alert")
    refute view |> has_element?("#account-confirmation-modal")
  end

  test "Users who have their account not confirmed but created them within 48 hours only see the confirmation alert not the modal",
       %{conn: conn} do
    user = insert(:user, confirmed_at: nil, inserted_at: DateTime.utc_now())

    {:ok, view, _html} =
      conn |> log_in_user(user) |> live("/projects", on_error: :raise)

    assert view |> has_element?("#account-confirmation-alert")
    refute view |> has_element?("#account-confirmation-modal")
  end

  test "Users who have their account not confirmed but created them within 48 hours dont see the alert and modal if email verification isn't enabled",
       %{conn: conn} do
    Mox.stub(
      Lightning.MockConfig,
      :check_flag?,
      fn :require_email_verification -> false end
    )

    user = insert(:user, confirmed_at: nil, inserted_at: DateTime.utc_now())

    {:ok, view, _html} =
      conn |> log_in_user(user) |> live("/projects", on_error: :raise)

    refute view |> has_element?("#account-confirmation-alert")
    refute view |> has_element?("#account-confirmation-modal")
  end

  test "Users who have their account not confirmed but created them after 48 hours see both the confirmation alert and the modal",
       %{conn: conn} do
    user =
      insert(:user,
        confirmed_at: nil,
        inserted_at: DateTime.utc_now() |> Timex.shift(hours: -50)
      )

    {:ok, view, _html} =
      conn |> log_in_user(user) |> live("/projects", on_error: :raise)

    refute view |> has_element?("#account-confirmation-alert")
    assert view |> has_element?("#account-confirmation-modal")
  end

  test "Users who have their account not confirmed but created them after 48 hours dont see the alert and modal when verification is disabled",
       %{conn: conn} do
    Mox.stub(
      Lightning.MockConfig,
      :check_flag?,
      fn :require_email_verification -> false end
    )

    user =
      insert(:user,
        confirmed_at: nil,
        inserted_at: DateTime.utc_now() |> Timex.shift(hours: -50)
      )

    {:ok, view, _html} =
      conn |> log_in_user(user) |> live("/projects", on_error: :raise)

    refute view |> has_element?("#account-confirmation-alert")
    refute view |> has_element?("#account-confirmation-modal")
  end
end
