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
    {:ok, _view, html} = live(conn, ~p"/profile/auth/backup_codes")
    assert html =~ "Recovery codes"

    for backup_code <- user.backup_codes do
      assert html =~ backup_code.code
    end
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

    assert view
           |> has_element?(
             "#project-picker-option-#{project_1.id}",
             project_1.name
           )

    assert view
           |> has_element?(
             "#project-picker-option-#{project_2.id}",
             project_2.name
           )

    refute view
           |> has_element?(
             "#project-picker-option-#{project_3.id}",
             project_3.name
           )
  end

  test "user can regenerate backup codes", %{
    conn: conn,
    user: user
  } do
    {:ok, view, _html} =
      live(conn, ~p"/profile/auth/backup_codes", on_error: :raise)

    render_click(view, "regenerate-backup-codes", %{})

    html = render(view)

    for backup_code <- user.backup_codes do
      # old codes dont exist
      refute html =~ backup_code.code
    end

    backup_codes = Accounts.list_user_backup_codes(user)

    for backup_code <- backup_codes do
      assert html =~ backup_code.code
    end
  end
end
