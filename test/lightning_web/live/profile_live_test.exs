defmodule LightningWeb.ProfileLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.AccountsFixtures
  import Lightning.Factories
  import Swoosh.TestAssertions

  @update_password_attrs %{
    current_password: valid_user_password(),
    password: "password1",
    password_confirmation: "password1"
  }

  @invalid_empty_password_attrs %{
    current_password: "",
    password: "",
    password_confirmation: ""
  }

  @invalid_schedule_deletion_attrs %{
    scheduled_deletion_email: "invalid@email.com"
  }

  @invalid_too_short_password_attrs %{
    current_password: "",
    password: "abc",
    password_confirmation: ""
  }

  @invalid_dont_match_password_attrs %{
    current_password: "",
    password: "password1",
    password_confirmation: "password2"
  }

  @invalid_email_update_attrs %{
    email: ""
  }

  @update_email_attrs %{
    email: "new@example.com"
  }

  describe "Edit user profile" do
    setup :register_and_log_in_user

    test "load edit page", %{conn: conn} do
      {:ok, _profile_live, html} =
        live(conn, Routes.profile_edit_path(conn, :edit))

      assert html =~ "Change email"
      assert html =~ "Change password"
    end

    test "save password", %{conn: conn} do
      {:ok, profile_live, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit))

      assert profile_live
             |> form("#password_form", user: @invalid_empty_password_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert profile_live
             |> form("#password_form", user: @invalid_dont_match_password_attrs)
             |> render_change() =~ "Your passwords do not match"

      assert profile_live
             |> form("#password_form", user: @invalid_too_short_password_attrs)
             |> render_change() =~ "Password minimum length is 8 characters"

      assert profile_live
             |> form("#password_form", user: @invalid_empty_password_attrs)
             |> render_submit() =~ "can&#39;t be blank"

      assert profile_live
             |> form("#password_form", user: @invalid_dont_match_password_attrs)
             |> render_submit() =~ "Your passwords do not match"

      assert profile_live
             |> form("#password_form", user: @invalid_too_short_password_attrs)
             |> render_submit() =~ "Password minimum length is 8 characters"

      {:ok, conn} =
        profile_live
        |> form("#password_form", user: @update_password_attrs)
        |> render_submit()
        |> follow_redirect(conn)

      assert "/" = redirected_path = redirected_to(conn, 302)

      html =
        get(recycle(conn), redirected_path)
        |> html_response(200)

      assert html =~ "Password changed successfully."
      assert html =~ "Projects"
    end

    test "validate password confirmation", %{conn: conn} do
      {:ok, profile_live, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit))

      assert profile_live
             |> form("#email_form", user: %{current_password: "invalid"})
             |> render_change() =~ "Your passwords do not match."
    end

    test "validate email", %{conn: conn, user: user} do
      {:ok, profile_live, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit))

      assert profile_live
             |> form("#email_form", user: %{email: user.email})
             |> render_change() =~ "Please change your email"
    end

    test "a user can change their email address", %{conn: conn} do
      {:ok, profile_live, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit))

      assert profile_live
             |> form("#email_form", user: @invalid_email_update_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert profile_live
             |> form("#email_form", user: %{email: "oops email"})
             |> render_change() =~ "Email address not valid."

      assert profile_live
             |> form("#email_form", user: @update_email_attrs)
             |> render_submit() =~ "Sending confirmation email..."
    end

    test "allows a user to schedule their own account for deletion", %{
      conn: conn,
      user: user
    } do
      {:ok, profile_live, html} =
        live(conn, Routes.profile_edit_path(conn, :edit))

      assert html =~ "Delete my account"

      {:ok, new_live, html} =
        profile_live
        |> element("a", "Delete my account")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.profile_edit_path(conn, :delete, user)
        )

      assert html =~
               "This user&#39;s account and credential data will be deleted"

      assert new_live
             |> form("#scheduled_deletion_form",
               user: @invalid_schedule_deletion_attrs
             )
             |> render_change() =~
               "This email doesn&#39;t match your current email"

      new_live
      |> form("#scheduled_deletion_form",
        user: %{
          scheduled_deletion_email: user.email
        }
      )
      |> render_submit()
      |> follow_redirect(conn, Routes.user_session_path(conn, :delete))

      assert_email_sent(subject: "Lightning Account Deletion", to: user.email)
    end

    test "users can't schedule deletion for other users", %{
      conn: conn,
      user: _user
    } do
      another_user = user_fixture()

      {:ok, _profile_live, html} =
        live(conn, ~p"/profile/#{another_user.id}/delete")
        |> follow_redirect(conn)

      assert html =~ "You can&#39;t perform this action"
    end

    test "user cancels deletion", %{
      conn: conn,
      user: user
    } do
      {:ok, profile_live, html} =
        live(conn, Routes.profile_edit_path(conn, :edit))

      assert html =~ "Delete my account"

      {:ok, new_live, html} =
        profile_live
        |> element("a", "Delete my account")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.profile_edit_path(conn, :delete, user)
        )

      assert html =~
               "This user&#39;s account and credential data will be deleted"

      {:ok, _new_live, html} =
        new_live
        |> element("button", "Cancel")
        |> render_click()
        |> follow_redirect(
          conn,
          Routes.profile_edit_path(conn, :edit)
        )

      assert html =~ "User Profile"
    end
  end

  describe "MFA Component for a user without MFA enabled" do
    setup :register_and_log_in_user

    test "on clicking the toggle button a QR code is generated", %{conn: conn} do
      {:ok, view, html} = live(conn, Routes.profile_edit_path(conn, :edit))

      refute html =~
               "You have configured an authentication app to get two-factor authentication codes"

      refute html =~ "Scan the QR code"

      # show QR code
      assert view |> element("#toggle-mfa-switch") |> render_click() =~
               "Scan the QR code"

      # hide QR code
      view |> element("#toggle-mfa-switch") |> render_click()

      refute render(view) =~ "Scan the QR code"
    end

    test "user can successfully add MFA to their account", %{
      conn: conn,
      user: user
    } do
      Application.put_env(:lightning, :totp_client, LightningTest.TOTP)

      {:ok, view, _html} = live(conn, Routes.profile_edit_path(conn, :edit))

      refute view |> form("#set_totp_form") |> has_element?()

      assert view |> element("#toggle-mfa-switch") |> render_click() =~
               "Scan the QR code"

      assert view |> form("#set_totp_form") |> has_element?()

      secret = LightningTest.TOTP.secret()
      valid_code = NimbleTOTP.verification_code(secret)

      view
      |> form("#set_totp_form", user_totp: %{code: valid_code})
      |> render_submit()

      user_token =
        Lightning.Repo.get_by!(Lightning.Accounts.UserToken,
          user_id: user.id,
          context: "sudo_session"
        )

      flash =
        assert_redirected(
          view,
          Routes.backup_codes_index_path(conn, :index,
            sudo_token: Base.encode64(user_token.token)
          )
        )

      assert flash["info"] == "2FA Setup successfully!"
    end
  end

  describe "MFA Component for a user with MFA enabled" do
    setup %{conn: conn} do
      user =
        insert(:user,
          mfa_enabled: true,
          user_totp: build(:user_totp),
          backup_codes: build_list(10, :backup_code)
        )

      %{user: user, conn: log_in_user(conn, user)}
    end

    test "the user sees an option to setup another device", %{
      conn: conn
    } do
      {:ok, view, html} = live(conn, Routes.profile_edit_path(conn, :edit))

      assert html =~
               "You have configured an authentication app to get two-factor authentication codes"

      assert view |> element("a#setup_another_totp_device") |> has_element?()
      refute html =~ "Scan the QR code"

      # show QR code
      html = view |> element("a#setup_another_totp_device") |> render_click()
      assert html =~ "Scan the QR code"
      refute view |> element("a#setup_another_totp_device") |> has_element?()
    end

    test "user can disable MFA from their account", %{conn: conn} do
      {:ok, view, _html} = live(conn, Routes.profile_edit_path(conn, :edit))

      result = view |> element("#disable_mfa_button") |> render_click()

      {:ok, view, html} = follow_redirect(result, conn)
      assert html =~ "2FA Disabled successfully!"

      refute render(view) =~
               "You have configured an authentication app to get two-factor authentication codes"
    end

    test "user can successfully setup another device", %{conn: conn} do
      Application.put_env(:lightning, :totp_client, LightningTest.TOTP)

      {:ok, view, _html} = live(conn, Routes.profile_edit_path(conn, :edit))

      refute view |> form("#set_totp_form") |> has_element?()

      assert view |> element("a#setup_another_totp_device") |> render_click() =~
               "Scan the QR code"

      assert view |> form("#set_totp_form") |> has_element?()

      secret = LightningTest.TOTP.secret()
      valid_code = NimbleTOTP.verification_code(secret)

      view
      |> form("#set_totp_form", user_totp: %{code: valid_code})
      |> render_submit()

      flash = assert_redirected(view, Routes.profile_edit_path(conn, :edit))
      assert flash["info"] == "2FA Setup successfully!"
    end
  end
end
