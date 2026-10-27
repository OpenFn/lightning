defmodule LightningWeb.ProfileLiveTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.AccountsFixtures
  import Lightning.Factories
  import Lightning.GDPRHelpers
  import LightningWeb.DesignSystemHelpers
  import Mox
  import Phoenix.LiveViewTest
  import Swoosh.TestAssertions

  alias Lightning.Accounts
  alias LightningWeb.ProfileLive.Edit
  alias Swoosh.Email.Recipient

  setup :verify_on_exit!

  @page "#profile-page"

  @update_password_attrs %{
    "currentPassword" => valid_user_password(),
    "password" => "password1234",
    "passwordConfirmation" => "password1234"
  }

  defp props(view), do: page_props(view, @page)

  defp send_event(view, event, payload \\ %{}),
    do: push_page_event(view, @page, event, payload)

  defp basic_info(attrs) do
    Map.merge(
      %{
        "firstName" => "Kylian",
        "lastName" => "Mbappe",
        "contactPreference" => "critical"
      },
      attrs
    )
  end

  describe "Edit user profile" do
    setup :register_and_log_in_user

    test "load edit page", %{conn: conn, user: user} do
      {:ok, view, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit), on_error: :raise)

      assert %{
               "user" => %{"id" => id, "email" => email},
               "mfa" => %{"enabled" => false},
               "github" => %{"status" => "none"},
               "experimentalFeatures" => false,
               "deletion" => %{
                 "href" => href,
                 "hasActivityInProjects" => false,
                 "blocked" => false
               },
               "deleting" => false
             } = props(view)

      assert id == user.id
      assert email == user.email
      assert href == ~p"/profile/#{user.id}/delete"
    end

    test "update basic information", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)

      send_event(view, "save_basic_info", basic_info(%{"firstName" => ""}))

      assert_reply(view, %{
        fieldErrors: %{"firstName" => ["This field can't be blank."]}
      })

      send_event(view, "save_basic_info", basic_info(%{"lastName" => ""}))

      assert_reply(view, %{
        fieldErrors: %{"lastName" => ["This field can't be blank."]}
      })

      send_event(
        view,
        "save_basic_info",
        basic_info(%{"firstName" => "Kylian\u0007"})
      )

      assert_reply(view, %{fieldErrors: %{"firstName" => [message]}})
      assert message =~ "can't contain control characters"

      assert Repo.reload(user).first_name == user.first_name

      assert send_event(view, "save_basic_info", basic_info(%{})) =~
               "User information updated successfully"

      assert %{
               first_name: "Kylian",
               last_name: "Mbappe",
               contact_preference: :critical
             } = Repo.reload(user)

      assert %{"firstName" => "Kylian", "lastName" => "Mbappe"} =
               props(view)["user"]
    end

    test "a field left out of the save keeps its value", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)

      send_event(view, "save_basic_info", %{
        "firstName" => "Kylian",
        "lastName" => "Mbappe"
      })

      assert Repo.reload(user).contact_preference == user.contact_preference
      assert props(view)["user"]["contactPreference"]
    end

    test "save password", %{conn: conn, user: user} do
      {:ok, view, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit), on_error: :raise)

      send_event(view, "change_password", %{
        "currentPassword" => valid_user_password(),
        "password" => "",
        "passwordConfirmation" => ""
      })

      assert_reply(view, %{
        fieldErrors: %{"password" => ["This field can't be blank."]}
      })

      send_event(view, "change_password", %{
        @update_password_attrs
        | "passwordConfirmation" => "password4567"
      })

      assert_reply(view, %{
        fieldErrors: %{
          "passwordConfirmation" => ["Your passwords do not match."]
        }
      })

      send_event(view, "change_password", %{
        "currentPassword" => valid_user_password(),
        "password" => "abc",
        "passwordConfirmation" => "abc"
      })

      assert_reply(view, %{fieldErrors: %{"password" => [message]}})
      assert message =~ "Password minimum length is 12 characters"

      send_event(view, "change_password", %{
        @update_password_attrs
        | "currentPassword" => "not the password"
      })

      assert_reply(view, %{fieldErrors: %{"currentPassword" => ["is not valid"]}})

      assert Accounts.get_user_by_email_and_password(
               user.email,
               valid_user_password()
             )

      {:ok, conn} =
        view
        |> send_event("change_password", @update_password_attrs)
        |> follow_redirect(conn)

      assert "/projects" = redirected_path = redirected_to(conn, 302)

      html =
        get(recycle(conn), redirected_path)
        |> html_response(200)

      assert html =~ "Password changed successfully."
      assert Accounts.get_user_by_email_and_password(user.email, "password1234")
    end

    test "a wrong current password refuses the email change", %{conn: conn} do
      {:ok, view, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit), on_error: :raise)

      send_event(view, "change_email", %{
        "email" => "new_email_123@openfn.org",
        "currentPassword" => "invalid"
      })

      assert_reply(view, %{fieldErrors: %{"currentPassword" => [_]}})
      refute_email_sent()
    end

    test "validate email", %{conn: conn, user: user} do
      {:ok, view, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit), on_error: :raise)

      send_event(view, "change_email", %{
        "email" => user.email,
        "currentPassword" => valid_user_password()
      })

      assert_reply(view, %{
        fieldErrors: %{"email" => ["Please change your email" | _]}
      })
    end

    test "a user can change their email address", %{conn: conn, user: user} do
      {:ok, view, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit), on_error: :raise)

      send_event(view, "change_email", %{
        "email" => "",
        "currentPassword" => valid_user_password()
      })

      assert_reply(view, %{
        fieldErrors: %{"email" => ["This field can't be blank."]}
      })

      send_event(view, "change_email", %{
        "email" => "oops email",
        "currentPassword" => valid_user_password()
      })

      assert_reply(view, %{
        fieldErrors: %{"email" => ["Email address not valid."]}
      })

      refute_email_sent()

      assert send_event(view, "change_email", %{
               "email" => "new@example.com",
               "currentPassword" => valid_user_password()
             }) =~ "You will receive an email with instructions shortly."

      assert_email_sent(to: Recipient.format(user))

      assert_email_sent(fn email ->
        assert [{_, "new@example.com"}] = email.to
      end)
    end

    test "allows a user to schedule their own account for deletion", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit), on_error: :raise)

      %{"deletion" => %{"href" => href}, "deleting" => false} = props(view)
      assert href == Routes.profile_edit_path(conn, :delete, user)

      {:ok, view, _html} = live(conn, href, on_error: :raise)
      assert props(view)["deleting"]

      send_event(view, "delete_account", %{"email" => "invalid@email.com"})

      assert_reply(view, %{error: "This email doesn't match your current email"})
      refute Repo.reload(user).scheduled_deletion

      send_event(view, "delete_account", %{"email" => user.email})

      flash =
        assert_redirect(view, Routes.user_session_path(conn, :delete))

      assert flash["info"] == "User scheduled for deletion"
      assert Repo.reload(user).scheduled_deletion

      assert_email_sent(
        subject: "Your account has been scheduled for deletion",
        to: Recipient.format(user)
      )
    end

    test "users can't schedule deletion for other users", %{
      conn: conn,
      user: user
    } do
      another_user = user_fixture()

      assert {:error, {:live_redirect, %{to: "/profile", flash: flash}}} =
               live(conn, ~p"/profile/#{another_user.id}/delete")

      assert flash["error"] == "You can't perform this action"

      {:ok, _view, html} =
        live(conn, ~p"/profile/#{another_user.id}/delete")
        |> follow_redirect(conn)

      assert html =~ "You can&#39;t perform this action"

      assert {:error, {:live_redirect, %{to: "/profile"}}} =
               live(conn, ~p"/profile/not-an-id/delete")

      refute Repo.reload(another_user).scheduled_deletion
      refute Repo.reload(user).scheduled_deletion
    end

    test "an instance's own deletion modal replaces Lightning's", %{
      conn: conn,
      user: user
    } do
      socket = %Phoenix.LiveView.Socket{
        assigns: %{
          __changed__: %{},
          current_user: user,
          deleting: true,
          hosted_delete_modal: __MODULE__.HostedDeletionModal
        }
      }

      assert {:reply, %{error: "You can't perform this action"}, _socket} =
               Edit.handle_event(
                 "delete_account",
                 %{"email" => user.email},
                 socket
               )

      refute Repo.reload(user).scheduled_deletion

      {:ok, view, html} =
        live_isolated(conn, __MODULE__.ProfileTemplate,
          session: %{"user" => user, "modal" => __MODULE__.HostedDeletionModal}
        )

      assert html =~ "hosted deletion modal"
      refute props(view)["deleting"]
    end

    test "deletion is refused unless the deletion modal is open", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)

      send_event(view, "delete_account", %{"email" => user.email})

      assert_reply(view, %{error: "You can't perform this action"})
      refute Repo.reload(user).scheduled_deletion
    end
  end

  describe "MFA Component for a user without MFA enabled" do
    setup :register_and_log_in_user

    setup do
      Application.put_env(:lightning, :totp_client, LightningTest.TOTP)
    end

    test "starting setup replies with the QR code and the secret, only there",
         %{conn: conn} do
      {:ok, view, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit), on_error: :raise)

      send_event(view, "start_mfa_setup")

      secret = Base.encode32(LightningTest.TOTP.secret(), padding: false)

      assert_reply(view, %{
        secret: ^secret,
        qrCodeSrc: "data:image/svg+xml;base64," <> svg
      })

      assert svg |> Base.decode64!() =~ "<svg"
      refute render(view) =~ secret
    end

    test "user can successfully add MFA to their account", %{
      conn: conn,
      user: user
    } do
      {:ok, view, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit), on_error: :raise)

      send_event(view, "start_mfa_setup")

      valid_code = NimbleTOTP.verification_code(LightningTest.TOTP.secret())
      send_event(view, "confirm_mfa", %{"code" => valid_code})

      user_token =
        Repo.get_by!(Accounts.UserToken,
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
      assert Repo.reload(user).mfa_enabled
    end

    test "a wrong code is refused on the code field", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)
      send_event(view, "start_mfa_setup")

      send_event(view, "confirm_mfa", %{"code" => "000000"})

      assert_reply(view, %{fieldErrors: %{"code" => [_]}})
      refute Repo.reload(user).mfa_enabled
    end

    test "a code is refused before setup starts", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)

      code = NimbleTOTP.verification_code(LightningTest.TOTP.secret())
      send_event(view, "confirm_mfa", %{"code" => code})

      assert_reply(view, %{error: "Invalid request"})
      refute Accounts.get_user_totp(user)
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

    test "user can disable MFA from their account", %{conn: conn, user: user} do
      {:ok, view, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit), on_error: :raise)

      assert props(view)["mfa"]["enabled"]

      assert send_event(view, "disable_mfa") =~ "MFA Disabled"

      refute props(view)["mfa"]["enabled"]
      refute Accounts.get_user_totp(user)
    end

    test "user can successfully setup another device", %{conn: conn} do
      Application.put_env(:lightning, :totp_client, LightningTest.TOTP)

      {:ok, view, _html} =
        live(conn, Routes.profile_edit_path(conn, :edit), on_error: :raise)

      send_event(view, "start_mfa_setup")

      valid_code = NimbleTOTP.verification_code(LightningTest.TOTP.secret())

      assert send_event(view, "confirm_mfa", %{"code" => valid_code}) =~
               "MFA Setup"
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
      assert props(view)["github"]["status"] == "none"

      # mock redirect from github
      get(conn, ~p"/oauth/github/callback?code=123456")

      flash = assert_redirect(view, ~p"/profile")

      assert flash["info"] == "GitHub account linked successfully"

      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)

      assert props(view)["github"]["status"] == "connected"
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
      assert props(view)["github"]["status"] == "none"

      # mock redirect from github
      get(conn, ~p"/oauth/github/callback?code=123456")

      :ok = refute_redirected(view, ~p"/profile")

      assert render(view) =~
               "Oops! GitHub account failed to link. Please try again"

      # the user can still connect
      assert %{"status" => "none", "connectHref" => href} = props(view)["github"]
      assert href =~ "https://github.com/login/oauth/authorize?"
    end

    test "users see option to reconnect if the refresh token has expired", %{
      conn: conn,
      user: user
    } do
      # active refresh token
      set_github_token(user, %{
        "access_token" => "access-token",
        "refresh_token" => "refresh-token",
        "expires_at" => DateTime.utc_now() |> DateTime.add(-20),
        "refresh_token_expires_at" => DateTime.utc_now() |> DateTime.add(20)
      })

      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)
      assert props(view)["github"]["status"] == "connected"

      # expired refresh token
      set_github_token(user, %{
        "access_token" => "access-token",
        "refresh_token" => "refresh-token",
        "expires_at" => DateTime.utc_now() |> DateTime.add(-20),
        "refresh_token_expires_at" => DateTime.utc_now() |> DateTime.add(-20)
      })

      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)

      assert %{"status" => "expired", "connectHref" => href} =
               props(view)["github"]

      assert href =~ "https://github.com/login/oauth/authorize?"
    end

    test "users can disconnect their github accounts using non-expiry access tokens",
         %{
           conn: conn,
           user: user
         } do
      set_github_token(user, %{"access_token" => "1234567"})

      expect_grant_deleted({:ok, %Tesla.Env{status: 204}})

      assert_disconnects(conn, user)
    end

    test "users can disconnect their github accounts using expiry access tokens",
         %{
           conn: conn,
           user: user
         } do
      # expired access token
      set_github_token(user, %{
        "access_token" => "access-token",
        "refresh_token" => "refresh-token",
        "expires_at" => DateTime.utc_now() |> DateTime.add(-20),
        "refresh_token_expires_at" => DateTime.utc_now() |> DateTime.add(1000)
      })

      url_to_delete = grant_url()
      url_to_refresh_token = "https://github.com/login/oauth/access_token"

      Mox.expect(Lightning.Tesla.Mock, :call, 2, fn
        %{url: ^url_to_refresh_token}, _opts ->
          {:ok, %Tesla.Env{body: %{"access_token" => "updated-access-token"}}}

        %{url: ^url_to_delete}, _opts ->
          {:ok, %Tesla.Env{status: 204}}
      end)

      assert_disconnects(conn, user)
    end

    test "users can disconnect their github accounts successfully even when the api returns error",
         %{
           conn: conn,
           user: user
         } do
      set_github_token(user, %{"access_token" => "1234567"})

      expect_grant_deleted({:ok, %Tesla.Env{status: 403}})

      assert_disconnects(conn, user)
    end

    defp set_github_token(user, token) do
      user
      |> Ecto.Changeset.change(%{github_oauth_token: token})
      |> Repo.update!()
    end

    defp grant_url do
      client_id = Application.fetch_env!(:lightning, :github_app)[:client_id]
      "https://api.github.com/applications/#{client_id}/grant"
    end

    defp expect_grant_deleted(response) do
      url = grant_url()

      Mox.expect(Lightning.Tesla.Mock, :call, fn %{url: ^url}, _opts ->
        response
      end)
    end

    defp assert_disconnects(conn, user) do
      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)
      assert props(view)["github"]["status"] == "connected"

      assert send_event(view, "disconnect_github") =~
               "GitHub connection removed successfully"

      assert props(view)["github"]["status"] == "none"
      assert is_nil(Repo.reload(user).github_oauth_token)
    end
  end

  describe "experimental features toggle" do
    setup :register_and_log_in_user

    test "renders experimental features section with default disabled state", %{
      conn: conn
    } do
      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)

      assert props(view)["experimentalFeatures"] == false
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

      {:ok, view, _html} =
        conn
        |> log_in_user(user_with_prefs)
        |> live(~p"/profile", on_error: :raise)

      assert props(view)["experimentalFeatures"] == true
    end

    test "toggles experimental features on", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)

      assert send_event(view, "set_experimental_features", %{"on" => true}) =~
               "Experimental features updated successfully"

      assert Repo.reload(user).preferences["experimental_features"] == true
      assert props(view)["experimentalFeatures"] == true
    end

    test "toggles experimental features off", %{conn: conn, user: user} do
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

      send_event(view, "set_experimental_features", %{"on" => false})

      assert Repo.reload(user_with_prefs).preferences["experimental_features"] ==
               false

      assert props(view)["experimentalFeatures"] == false
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

      send_event(view, "set_experimental_features", %{"on" => true})

      assert Repo.reload(user_with_prefs).preferences == %{
               "existing_pref" => "value",
               "experimental_features" => true
             }
    end

    test "refuses a missing or non-boolean value", %{conn: conn, user: user} do
      {:ok, view, _html} = live(conn, ~p"/profile", on_error: :raise)

      send_event(view, "set_experimental_features", %{})
      assert_reply(view, %{error: "Invalid request"})

      send_event(view, "set_experimental_features", %{"on" => "yes"})
      assert_reply(view, %{error: "Invalid request"})

      assert Repo.reload(user).preferences == %{}
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

  # The profile template with the delete route open on a configured modal.
  defmodule ProfileTemplate do
    use Phoenix.LiveView

    def mount(_params, %{"user" => user, "modal" => modal}, socket) do
      {:ok,
       assign(socket,
         current_user: user,
         deleting: true,
         hosted_delete_modal: modal,
         github_connect_href: nil,
         github_status: "none",
         deletion: %{href: "", hasActivityInProjects: false, blocked: false},
         gdpr_preferences: nil
       )}
    end

    def render(assigns), do: Edit.render(assigns)
  end

  defmodule HostedDeletionModal do
    use Phoenix.LiveComponent

    def render(assigns), do: ~H"<div>hosted deletion modal</div>"
  end
end
