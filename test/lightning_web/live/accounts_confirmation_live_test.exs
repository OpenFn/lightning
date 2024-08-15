defmodule LightningWeb.AccountsConfirmationLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  test "Users who have their accounts confirmed do not see the banner nor the modal in the sessions",
       %{conn: conn} do
    user = insert(:user, confirmed_at: DateTime.utc_now())

    {:ok, view, _html} = conn |> log_in_user(user) |> live("/projects")

    refute view |> has_element?("#account-confirmation-alert")
    refute view |> has_element?("#account-confirmation-modal")
  end

  test "Users who have their account not confirmed but created them within 48 hours only see the confirmation alert not the modal",
       %{conn: conn} do
    user = insert(:user, confirmed_at: nil, inserted_at: DateTime.utc_now())

    {:ok, view, _html} = conn |> log_in_user(user) |> live("/projects")

    assert view |> has_element?("#account-confirmation-alert")
    refute view |> has_element?("#account-confirmation-modal")
  end

  test "Users who have their account not confirmed but created them after 48 hours see both the confirmation alert and the modal",
       %{conn: conn} do
    user =
      insert(:user,
        confirmed_at: nil,
        inserted_at: DateTime.utc_now() |> Timex.shift(hours: -50)
      )

    {:ok, view, _html} = conn |> log_in_user(user) |> live("/projects")

    refute view |> has_element?("#account-confirmation-alert")
    assert view |> has_element?("#account-confirmation-modal")
  end
end
