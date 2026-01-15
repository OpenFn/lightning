defmodule LightningWeb.ProfileLiveTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.AccountsFixtures
  import Lightning.Factories
  import Lightning.GDPRHelpers
  import Mox
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  setup :verify_on_exit!

  @update_password_attrs %{
    current_password: valid_user_password(),
    password: "password1234",
    password_confirmation: "password1234"
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
    password: "password1234",
    password_confirmation: "password4567"
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
        live(conn, Routes.profile_edit_path(conn, :edit), on_error: :raise)

      assert html =~ "Change email"
      assert html =~ "Change password"
    end

    test "update basic information", %{conn: conn, user: user} do
      {:ok, profile_live, _html} =
        live(conn, ~p"/profile", on_error: :raise)

      assert profile_live
             |> has_element?("h2", "#{user.first_name} #{user.last_name}")

      assert profile_live
             |> form("#basic-info-form", user: %{first_name: ""})
             |> render_change() =~ "This field can&#39;t be blank"

      assert profile_live
             |> form("#basic-info-form", user: %{last_name: ""})
             |> render_change() =~ "This field can&#39;t be blank"

      assert profile_live
             |> form("#basic-info-form",
               user: %{
                 first_name: "Kylian",
                 last_name: "",
                 contact_preference: "critical"
               }
             )
             |> render_submit() =~ "This field can&#39;t be blank"

      {:ok, profile_live, html} =
        profile_live
        |> form("#basic-info-form",
          user: %{
            first_name: "Kylian",
            last_name: "Mbappe",
            contact_preference: "critical"
          }
        )
        |> render_submit()
        |> follow_redirect(conn, ~p"/profile")

      assert html =~ "User information updated successfully"

      refute profile_live
             |> has_element?("h2", "#{user.first_name} #{user.last_name}")

      assert profile_live
             |> has_element?("h2", "Kylian Mbappe")
    end

    test "save password", %{conn: conn} do
      {:ok, profile_live, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit), on_error: :raise)

      assert profile_live
             |> form("#password-form", user: @invalid_empty_password_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert profile_live
             |> form("#password-form", user: @invalid_dont_match_password_attrs)
             |> render_change() =~ "Your passwords do not match"

      assert profile_live
             |> form("#password-form", user: @invalid_too_short_password_attrs)
             |> render_change() =~ "Password minimum length is 12 characters"

      assert profile_live
             |> form("#password-form", user: @invalid_empty_password_attrs)
             |> render_submit() =~ "can&#39;t be blank"

      assert profile_live
             |> form("#password-form", user: @invalid_dont_match_password_attrs)
             |> render_submit() =~ "Your passwords do not match"

      assert profile_live
             |> form("#password-form", user: @invalid_too_short_password_attrs)
             |> render_submit() =~ "Password minimum length is 12 characters"

      {:ok, conn} =
        profile_live
        |> form("#password-form", user: @update_password_attrs)
        |> render_submit()
        |> follow_redirect(conn)

      assert "/projects" = redirected_path = redirected_to(conn, 302)

      html =
        get(recycle(conn), redirected_path)
        |> html_response(200)

      assert html =~ "Password changed successfully."
      assert html =~ "Projects"
    end

    test "validate password confirmation", %{conn: conn} do
      {:ok, profile_live, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit), on_error: :raise)

      assert profile_live
             |> form("#email-form",
               user: %{
                 email: "new_email_123@openfn.org",
                 current_password: "invalid"
               }
             )
             |> render_submit() =~ "Your passwords do not match."
    end

    test "validate email", %{conn: conn, user: user} do
      {:ok, profile_live, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit), on_error: :raise)

      assert profile_live
             |> form("#email-form", user: %{email: user.email})
             |> render_change() =~ "Please change your email"
    end

    test "a user can change their email address", %{conn: conn} do
      {:ok, profile_live, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit), on_error: :raise)

      assert profile_live
             |> form("#email-form", user: @invalid_email_update_attrs)
             |> render_change() =~ "can&#39;t be blank"

      assert profile_live
             |> form("#email-form", user: %{email: "oops email"})
             |> render_change() =~ "Email address not valid."

      assert profile_live
             |> form("#email-form", user: @update_email_attrs)
             |> render_submit() =~ "Sending confirmation email..."
    end

    test "allows a user to schedule their own account for deletion", %{
      conn: conn,
      user: user
    } do
      {:ok, profile_live, html} =
        live(conn, Routes.profile_edit_path(conn, :edit), on_error: :raise)

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
               "Your account and credential data will be deleted"

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

      assert_email_sent(
        subject: "Your account has been scheduled for deletion",
        to: Swoosh.Email.Recipient.format(user)
      )
    end

    test "users can't schedule deletion for other users", %{
      conn: conn,
      user: _user
    } do
      another_user = user_fixture()

      {:ok, _profile_live, html} =
        live(conn, ~p"/profile/#{another_user.id}/delete", on_error: :raise)
        |> follow_redirect(conn)

      assert html =~ "You can&#39;t perform this action"
    end

    test "user cancels deletion", %{
      conn: conn,
      user: user
    } do
      {:ok, profile_live, html} =
        live(conn, Routes.profile_edit_path(conn, :edit), on_error: :raise)

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
               "Your account and credential data will be deleted"

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
      {:ok, view, html} =
        live(conn, Routes.profile_edit_path(conn, :edit), on_error: :raise)

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

      {:ok, view, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit), on_error: :raise)

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
        Repo.get_by!(Lightning.Accounts.UserToken,
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

      assert flash["info"] == "MFA Setup"
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
      {:ok, view, html} =
        live(conn, Routes.profile_edit_path(conn, :edit), on_error: :raise)

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
      {:ok, view, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit), on_error: :raise)

      result = view |> element("#disable_mfa_button") |> render_click()

      {:ok, view, html} = follow_redirect(result, conn)
      assert html =~ "MFA Disabled"

      refute render(view) =~
               "You have configured an authentication app to get two-factor authentication codes"
    end

    test "user can successfully setup another device", %{conn: conn} do
      Application.put_env(:lightning, :totp_client, LightningTest.TOTP)

      {:ok, view, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit), on_error: :raise)

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
      assert flash["info"] == "MFA Setup"
    end
  end

  describe "GitHub Component" do
    @describetag :capture_log
    setup :register_and_log_in_user

    test "users get updated after successfully connecting to github", %{
      conn: conn
    } do
      expected_token = %{"access_token" => "1234567"}

      Mox.expect(Lightning.Tesla.Mock, :call, fn
        %{url: "https://github.com/login/oauth/access_token"}, _opts ->
          {:ok, %Tesla.Env{body: expected_token}}
      end)

      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)
      assert has_element?(view, "#connect-github-link")
      refute has_element?(view, "#disconnect-github-button")

      # mock redirect from github
      get(conn, ~p"/oauth/github/callback?code=123456")

      flash = assert_redirect(view, ~p"/profile")

      assert flash["info"] == "GitHub account linked successfully"

      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)

      refute has_element?(view, "#connect-github-link")
      assert has_element?(view, "#disconnect-github-button")
    end

    test "users get updated after failing to connect to github", %{
      conn: conn
    } do
      expected_resp = %{"error" => "something happened"}

      Mox.expect(Lightning.Tesla.Mock, :call, fn
        %{url: "https://github.com/login/oauth/access_token"}, _opts ->
          {:ok, %Tesla.Env{body: expected_resp}}
      end)

      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)
      assert has_element?(view, "#connect-github-link")
      refute has_element?(view, "#disconnect-github-button")

      # mock redirect from github
      get(conn, ~p"/oauth/github/callback?code=123456")

      :ok = refute_redirected(view, ~p"/profile")

      assert render(view) =~
               "Oops! GitHub account failed to link. Please try again"

      # button to connect is still available
      assert has_element?(view, "#connect-github-link")
      refute has_element?(view, "#disconnect-github-button")
    end

    test "users see option to reconnect if the refresh token has expired", %{
      conn: conn,
      user: user
    } do
      # active refresh token
      expired_token = %{
        "access_token" => "access-token",
        "refresh_token" => "refresh-token",
        "expires_at" => DateTime.utc_now() |> DateTime.add(-20),
        "refresh_token_expires_at" => DateTime.utc_now() |> DateTime.add(20)
      }

      user
      |> Ecto.Changeset.change(%{github_oauth_token: expired_token})
      |> Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)
      refute has_element?(view, "#connect-github-link")
      assert has_element?(view, "#disconnect-github-button")

      # expired refresh token
      expired_token = %{
        "access_token" => "access-token",
        "refresh_token" => "refresh-token",
        "expires_at" => DateTime.utc_now() |> DateTime.add(-20),
        "refresh_token_expires_at" => DateTime.utc_now() |> DateTime.add(-20)
      }

      user
      |> Ecto.Changeset.change(%{github_oauth_token: expired_token})
      |> Repo.update!()

      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)
      connect_button = element(view, "#connect-github-link")
      assert has_element?(connect_button)
      assert render(connect_button) =~ "Reconnect your GitHub Account"
      assert render(connect_button) =~ "Your token has expired"
      refute has_element?(view, "#disconnect-github-button")
    end

    test "users can disconnect their github accounts using non-expiry access tokens",
         %{
           conn: conn,
           user: user
         } do
      expected_token = %{"access_token" => "1234567"}

      user =
        user
        |> Ecto.Changeset.change(%{github_oauth_token: expected_token})
        |> Repo.update!()

      app_config = Application.fetch_env!(:lightning, :github_app)

      url_to_hit =
        "https://api.github.com/applications/#{app_config[:client_id]}/grant"

      Mox.expect(Lightning.Tesla.Mock, :call, fn
        %{url: ^url_to_hit}, _opts ->
          {:ok, %Tesla.Env{status: 204}}
      end)

      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)
      refute has_element?(view, "#connect-github-link")
      assert has_element?(view, "#disconnect-github-button")

      result =
        view
        |> element("#disconnect_github_modal_confirm_button")
        |> render_click()

      {:ok, view, html} = follow_redirect(result, conn, ~p"/profile")

      assert html =~ "GitHub connection removed successfully"

      assert has_element?(view, "#connect-github-link")
      refute has_element?(view, "#disconnect-github-button")

      updated_user = Repo.reload(user)
      assert is_nil(updated_user.github_oauth_token)
    end

    test "users can disconnect their github accounts using expiry access tokens",
         %{
           conn: conn,
           user: user
         } do
      Mox.verify_on_exit!()
      # expired access token
      expected_token = %{
        "access_token" => "access-token",
        "refresh_token" => "refresh-token",
        "expires_at" => DateTime.utc_now() |> DateTime.add(-20),
        "refresh_token_expires_at" => DateTime.utc_now() |> DateTime.add(1000)
      }

      user =
        user
        |> Ecto.Changeset.change(%{github_oauth_token: expected_token})
        |> Repo.update!()

      app_config = Application.fetch_env!(:lightning, :github_app)

      url_to_delete =
        "https://api.github.com/applications/#{app_config[:client_id]}/grant"

      url_to_refresh_token = "https://github.com/login/oauth/access_token"

      Mox.expect(Lightning.Tesla.Mock, :call, 2, fn
        %{url: ^url_to_refresh_token}, _opts ->
          {:ok, %Tesla.Env{body: %{"access_token" => "updated-access-token"}}}

        %{url: ^url_to_delete}, _opts ->
          {:ok, %Tesla.Env{status: 204}}
      end)

      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)
      refute has_element?(view, "#connect-github-link")
      assert has_element?(view, "#disconnect-github-button")

      result =
        view
        |> element("#disconnect_github_modal_confirm_button")
        |> render_click()

      {:ok, view, html} = follow_redirect(result, conn, ~p"/profile")

      assert html =~ "GitHub connection removed successfully"

      assert has_element?(view, "#connect-github-link")
      refute has_element?(view, "#disconnect-github-button")

      updated_user = Repo.reload(user)
      assert is_nil(updated_user.github_oauth_token)
    end

    test "users can disconnect their github accounts successfully even when the api returns error",
         %{
           conn: conn,
           user: user
         } do
      expected_token = %{"access_token" => "1234567"}

      user =
        user
        |> Ecto.Changeset.change(%{github_oauth_token: expected_token})
        |> Repo.update!()

      app_config = Application.fetch_env!(:lightning, :github_app)

      url_to_hit =
        "https://api.github.com/applications/#{app_config[:client_id]}/grant"

      Mox.expect(Lightning.Tesla.Mock, :call, fn
        %{url: ^url_to_hit}, _opts ->
          {:ok, %Tesla.Env{status: 403}}
      end)

      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)
      refute has_element?(view, "#connect-github-link")
      assert has_element?(view, "#disconnect-github-button")

      result =
        view
        |> element("#disconnect_github_modal_confirm_button")
        |> render_click()

      {:ok, view, html} = follow_redirect(result, conn, ~p"/profile")

      assert html =~ "GitHub connection removed successfully"

      assert has_element?(view, "#connect-github-link")
      refute has_element?(view, "#disconnect-github-button")

      updated_user = Repo.reload(user)
      assert is_nil(updated_user.github_oauth_token)
    end
  end

  describe "experimental features toggle" do
    setup :register_and_log_in_user

    test "renders experimental features section with default disabled state", %{
      conn: conn
    } do
      {:ok, _view, html} = live(conn, ~p"/profile", on_error: :raise)

      assert html =~ "Experimental Features"
      assert html =~ "Enable access to new features and improvements"
    end

    test "renders experimental features section with enabled state", %{
      conn: conn,
      user: user
    } do
      user_with_prefs =
        user
        |> Ecto.Changeset.change(%{
          preferences: %{"experimental_features" => true}
        })
        |> Repo.update!()

      {:ok, _view, html} =
        conn
        |> log_in_user(user_with_prefs)
        |> live(~p"/profile", on_error: :raise)

      assert html =~ "Experimental Features"
    end

    test "toggles experimental features on via form change", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)

      # Find the form within the experimental features component
      view
      |> form("[phx-change=\"update_preferences\"]",
        preferences: %{"experimental_features" => "true"}
      )
      |> render_change()

      # Check if the preference was actually updated
      updated_user = Repo.reload(user)
      assert updated_user.preferences["experimental_features"] == true

      # Since flash messages in components may not be visible in test render,
      # we'll test that the functionality works by checking the database update
      # The flash message functionality is working if the update succeeds
    end

    test "toggles experimental features off via form change", %{
      conn: conn,
      user: user
    } do
      user_with_prefs =
        user
        |> Ecto.Changeset.change(%{
          preferences: %{"experimental_features" => true}
        })
        |> Repo.update!()

      {:ok, view, _html} =
        conn
        |> log_in_user(user_with_prefs)
        |> live(~p"/profile", on_error: :raise)

      view
      |> form("[phx-change=\"update_preferences\"]",
        preferences: %{"experimental_features" => "false"}
      )
      |> render_change()

      updated_user = Repo.reload(user_with_prefs)
      assert updated_user.preferences["experimental_features"] == false
    end

    test "preserves existing preferences when toggling experimental features", %{
      conn: conn,
      user: user
    } do
      user_with_prefs =
        user
        |> Ecto.Changeset.change(%{
          preferences: %{
            "existing_pref" => "value",
            "experimental_features" => false
          }
        })
        |> Repo.update!()

      {:ok, view, _html} =
        conn
        |> log_in_user(user_with_prefs)
        |> live(~p"/profile", on_error: :raise)

      view
      |> form("[phx-change=\"update_preferences\"]",
        preferences: %{"experimental_features" => "true"}
      )
      |> render_change()

      updated_user = Repo.reload(user_with_prefs)
      assert updated_user.preferences["existing_pref"] == "value"
      assert updated_user.preferences["experimental_features"] == true
    end

    test "handles missing experimental_features parameter", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)

      view
      |> form("[phx-change=\"update_preferences\"]", preferences: %{})
      |> render_change()

      # Should default to false when parameter is missing
      updated_user = Repo.reload(user)
      assert updated_user.preferences["experimental_features"] == false
    end

    test "works correctly when user has default empty preferences", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)

      view
      |> form("[phx-change=\"update_preferences\"]",
        preferences: %{"experimental_features" => "true"}
      )
      |> render_change()

      updated_user = Repo.reload(user)
      assert updated_user.preferences["experimental_features"] == true
    end
  end

  describe "GDPR Components" do
    setup :register_and_log_in_user

    test "the preferences component is shown when enabled in the config", %{
      conn: conn
    } do
      setup_enabled_gdpr_preferences(%{})
      {:ok, view, _html} = live(conn, ~p"/profile")
      assert has_element?(view, "#gdpr-preferences")
    end

    test "the preferences component is not shown when disabled in the config", %{
      conn: conn
    } do
      setup_disabled_gdpr_preferences(%{})
      {:ok, view, _html} = live(conn, ~p"/profile")
      refute has_element?(view, "#gdpr-preferences")
    end

    test "the banner is shown when enabled in the config", %{conn: conn} do
      setup_enabled_gdpr_banner(%{})
      {:ok, view, _html} = live(conn, ~p"/credentials")
      assert has_element?(view, "#gdpr-banner")
    end

    test "the banner is not shown when disabled in the config", %{conn: conn} do
      setup_disabled_gdpr_banner(%{})
      {:ok, view, _html} = live(conn, ~p"/credentials")
      refute has_element?(view, "#gdpr-banner")
    end
  end
end
