defmodule LightningWeb.UserSessionControllerTest do
  use LightningWeb.ConnCase, async: false

  import Lightning.AccountsFixtures
  import Lightning.Factories

  alias Lightning.AuthProviders

  import Mox

  # Enables a built-in social provider by setting its ENV-backed app config,
  # restoring the original value after the test.
  defp configure_sso_env(key) do
    original = Application.get_env(:lightning, key)

    Application.put_env(:lightning, key,
      client_id: "id",
      client_secret: "secret",
      redirect_uri: "http://localhost/authenticate/#{key}/callback"
    )

    on_exit(fn -> restore_env(key, original) end)
  end

  defp clear_sso_env(key) do
    original = Application.get_env(:lightning, key)
    Application.delete_env(:lightning, key)
    on_exit(fn -> restore_env(key, original) end)
  end

  defp restore_env(key, nil), do: Application.delete_env(:lightning, key)
  defp restore_env(key, value), do: Application.put_env(:lightning, key, value)

  # The admin-portal generic OIDC provider is persisted as an AuthConfig row.
  defp create_external_provider(name) do
    AuthProviders.create(%{
      name: name,
      client_id: "id",
      client_secret: "secret",
      discovery_url: "http://localhost/.well-known/openid-configuration",
      redirect_uri: "http://localhost/authenticate/#{name}/callback"
    })
  end

  setup :verify_on_exit!

  setup do
    %{user: user_fixture()}
  end

  describe "GET /users/log_in" do
    test "renders log in page", %{conn: conn} do
      stub(Lightning.MockConfig, :check_flag?, fn _flag ->
        true
      end)

      conn = get(conn, Routes.user_session_path(conn, :new))
      response = html_response(conn, 200)
      assert response =~ "Log in"
      assert response =~ "Register"
      assert response =~ "Forgot your password?"
      refute response =~ "via external provider"
    end

    test "register button is not available when signup is disabled", %{
      conn: conn
    } do
      stub(Lightning.MockConfig, :check_flag?, fn _flag ->
        false
      end)

      conn = get(conn, Routes.user_session_path(conn, :new))
      response = html_response(conn, 200)
      assert response =~ "Log in"
      refute response =~ "Register"
      assert response =~ "Forgot your password?"
      refute response =~ "via external provider"
    end

    test "redirects if already logged in", %{conn: conn, user: user} do
      conn =
        conn |> log_in_user(user) |> get(Routes.user_session_path(conn, :new))

      assert redirected_to(conn) == "/projects"
    end

    test "shows 'Sign in with' buttons when the SSO envs are configured", %{
      conn: conn
    } do
      configure_sso_env(:github_oauth)
      clear_sso_env(:google_oauth)

      conn = get(conn, Routes.user_session_path(conn, :new))
      response = html_response(conn, 200)

      assert response =~ "Sign in with GitHub"
      assert response =~ ~s(href="/authenticate/github")
      refute response =~ "via external provider"
    end

    test "shows the 'via external provider' button when configured in the admin portal",
         %{conn: conn} do
      clear_sso_env(:github_oauth)
      clear_sso_env(:google_oauth)

      {:ok, _config} = create_external_provider("keycloak")

      conn = get(conn, Routes.user_session_path(conn, :new))
      response = html_response(conn, 200)

      assert response =~ "via external provider"
      assert response =~ ~s(href="/authenticate/keycloak")
      refute response =~ "Sign in with"
    end

    test "social and external buttons are independent of each other", %{
      conn: conn
    } do
      configure_sso_env(:github_oauth)
      {:ok, _config} = create_external_provider("keycloak")

      conn = get(conn, Routes.user_session_path(conn, :new))
      response = html_response(conn, 200)

      # Both appear, neither suppresses the other.
      assert response =~ "Sign in with GitHub"
      assert response =~ "via external provider"
    end
  end

  describe "GET /users/exchange_token" do
    test "renders home as a logged in user for a valid token", %{
      conn: conn,
      user: user
    } do
      token = Lightning.Accounts.generate_auth_token(user)

      conn =
        get(
          conn,
          Routes.user_session_path(
            conn,
            :exchange_token,
            token |> Base.url_encode64()
          )
        )

      assert "/projects" = redirected_path = redirected_to(conn)

      response =
        get(recycle(conn), redirected_path)
        |> html_response(200)

      assert response =~ "User Profile"
    end

    test "renders log in page for an invalid token", %{conn: conn} do
      stub(Lightning.MockConfig, :check_flag?, fn _flag ->
        true
      end)

      conn = get(conn, Routes.user_session_path(conn, :exchange_token, "oops"))
      assert "/users/log_in" = redirected_path = redirected_to(conn)

      response =
        get(recycle(conn), redirected_path)
        |> html_response(200)

      assert response =~ "Invalid token"
      assert response =~ "Log in"
      assert response =~ "Register"
      assert response =~ "Forgot your password?"
    end

    test "redirects if already logged in", %{conn: conn, user: user} do
      conn =
        conn
        |> log_in_user(user)
        |> get(Routes.user_session_path(conn, :exchange_token, "oops"))

      assert redirected_to(conn) == "/projects"
    end
  end

  describe "POST /users/log_in" do
    setup do
      %{
        disabled_user: user_fixture(disabled: true),
        scheduled_deletion_user:
          user_fixture(
            scheduled_deletion: DateTime.utc_now() |> Timex.shift(days: 7)
          )
      }
    end

    test "logs the user in", %{conn: conn, user: user} do
      conn =
        post(conn, Routes.user_session_path(conn, :create), %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_token)
      assert redirected_to(conn) == "/projects"

      # Now do a logged in request and assert on the menu
      conn = get(conn, "/projects")
      response = html_response(conn, 200)
      assert response =~ "User Profile"
    end

    test "logs the user in but marks totp as pending for users wth MFA enabled",
         %{conn: conn} do
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))

      conn =
        post(conn, Routes.user_session_path(conn, :create), %{
          "user" => %{"email" => user.email, "password" => valid_user_password()}
        })

      assert get_session(conn, :user_totp_pending)

      assert redirected_to(conn) == Routes.user_totp_path(conn, :new)

      # The user is redirected to the TOTP page if they try accessing other pages
      conn = get(conn, "/")
      assert redirected_to(conn) == Routes.user_totp_path(conn, :new)
    end

    test "a user that has been scheduled for deletion can't log in", %{
      conn: conn,
      scheduled_deletion_user: scheduled_deletion_user
    } do
      conn =
        post(conn, Routes.user_session_path(conn, :create), %{
          "user" => %{
            "email" => scheduled_deletion_user.email,
            "password" => valid_user_password()
          }
        })

      response = html_response(conn, 200)
      assert response =~ "This user account is scheduled for deletion"
    end

    test "a disabled user can't log in", %{
      conn: conn,
      disabled_user: disabled_user
    } do
      conn =
        post(conn, Routes.user_session_path(conn, :create), %{
          "user" => %{
            "email" => disabled_user.email,
            "password" => valid_user_password()
          }
        })

      response = html_response(conn, 200)
      assert response =~ "This user account is disabled"
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      conn =
        post(conn, Routes.user_session_path(conn, :create), %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      assert conn.resp_cookies["_lightning_web_user_remember_me"]
      assert redirected_to(conn) == "/projects"
    end

    test "a user with MFA logging in with remember is redirected to TOTP page with remember_me query param",
         %{conn: conn} do
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))

      conn =
        post(conn, Routes.user_session_path(conn, :create), %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password(),
            "remember_me" => "true"
          }
        })

      refute conn.resp_cookies["_lightning_web_user_remember_me"]
      assert get_session(conn, :user_totp_pending)

      assert redirected_to(conn) ==
               Routes.user_totp_path(conn, :new, user: [remember_me: true])
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      conn =
        conn
        |> init_test_session(user_return_to: "/foo/bar")
        |> post(Routes.user_session_path(conn, :create), %{
          "user" => %{
            "email" => user.email,
            "password" => valid_user_password()
          }
        })

      assert redirected_to(conn) == "/foo/bar"
    end

    test "emits error message with invalid credentials", %{
      conn: conn,
      user: user
    } do
      conn =
        post(conn, Routes.user_session_path(conn, :create), %{
          "user" => %{"email" => user.email, "password" => "invalid_password"}
        })

      response = html_response(conn, 200)
      assert response =~ "Invalid email or password"
    end
  end

  describe "DELETE /users/log_out" do
    test "logs the user out", %{conn: conn, user: user} do
      conn =
        conn |> log_in_user(user) |> get(Routes.user_session_path(conn, :delete))

      assert redirected_to(conn) == "/users/log_in"
      refute get_session(conn, :user_token)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Logged out successfully"
    end

    test "succeeds even if the user is not logged in", %{conn: conn} do
      conn = get(conn, Routes.user_session_path(conn, :delete))
      assert redirected_to(conn) == "/users/log_in"
      refute get_session(conn, :user_token)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "Logged out successfully"
    end
  end
end
