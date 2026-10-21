defmodule LightningWeb.BackupCodesLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  alias Lightning.Accounts

  setup %{conn: conn} do
    user =
      insert(:user,
        mfa_enabled: true,
        user_totp: build(:user_totp),
        backup_codes: build_list(5, :backup_code)
      )

    sudo_token =
      user |> Accounts.generate_sudo_session_token() |> Base.encode64()

    conn = conn |> log_in_user(user) |> put_session(:sudo_token, sudo_token)
    %{user: user, conn: conn}
  end

  # The page is drawn by React from data-props.
  defp props(view), do: page_props(view, "#backup-codes-page")
  defp codes(view), do: Enum.map(props(view)["codes"], & &1["code"])

  test "without sudo_mode? enabled the user is redirected to the confirm accees page",
       %{conn: conn} do
    user =
      insert(:user,
        mfa_enabled: true,
        user_totp: build(:user_totp),
        backup_codes: build_list(5, :backup_code)
      )

    conn = log_in_user(conn, user)

    assert {:error, {:redirect, %{to: "/auth/confirm_access"}}} =
             live(conn, ~p"/profile/auth/backup_codes", on_error: :raise)
  end

  test "user with sudo_mode? enabled can view backup codes", %{
    conn: conn,
    user: user
  } do
    {:ok, view, html} = live(conn, ~p"/profile/auth/backup_codes")
    assert html =~ "Two-factor backup codes"

    assert props(view)["mfaEnabled"] == true

    assert Enum.sort(codes(view)) ==
             Enum.sort(Enum.map(user.backup_codes, & &1.code))

    assert Enum.all?(props(view)["codes"], &(&1["usedAt"] == nil))
  end

  test "a used code says when it was used", %{conn: conn, user: user} do
    [used | _] = user.backup_codes

    used
    |> Ecto.Changeset.change(used_at: ~U[2026-09-18 10:41:07.000000Z])
    |> Lightning.Repo.update!()

    {:ok, view, _html} = live(conn, ~p"/profile/auth/backup_codes")

    assert %{"usedAt" => "2026-09-18T10:41:07.000000Z"} =
             Enum.find(props(view)["codes"], &(&1["code"] == used.code))
  end

  test "a user without MFA is told so", %{conn: conn} do
    user = insert(:user, mfa_enabled: false)

    sudo_token =
      user |> Accounts.generate_sudo_session_token() |> Base.encode64()

    conn = conn |> log_in_user(user) |> put_session(:sudo_token, sudo_token)
    {:ok, view, _html} = live(conn, ~p"/profile/auth/backup_codes")

    assert props(view)["mfaEnabled"] == false
  end

  test "the project combobox is populated with the user's projects", %{
    conn: conn,
    user: user
  } do
    project_1 = insert(:project, project_users: [%{user: user, role: :owner}])

    project_2 = insert(:project, project_users: [%{user: user, role: :admin}])

    project_3 =
      insert(:project, project_users: [%{user: build(:user), role: :owner}])

    {:ok, view, _html} =
      live(conn, ~p"/profile/auth/backup_codes", on_error: :raise)

    # Project picker is a React component - check data-projects contains correct project IDs
    html = render(view)
    assert html =~ project_1.id
    assert html =~ project_2.id
    refute html =~ project_3.id
  end

  test "user can regenerate backup codes", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} =
      live(conn, ~p"/profile/auth/backup_codes", on_error: :raise)

    old_codes = Enum.map(user.backup_codes, & &1.code)

    assert push_page_event(view, "#backup-codes-page", "regenerate-backup-codes") =~
             "New Backup Codes Generated!"

    assert_reply(view, %{})

    shown = codes(view)
    assert length(shown) == 10
    assert shown -- old_codes == shown

    stored = user |> Accounts.list_user_backup_codes() |> Enum.map(& &1.code)
    assert Enum.sort(shown) == Enum.sort(stored)
  end
end
