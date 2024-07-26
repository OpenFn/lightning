defmodule LightningWeb.UserSessionControllerTest do
  use LightningWeb.ConnCase, async: false

  import Lightning.AccountsFixtures
  import Lightning.Factories

  alias Lightning.AuthProviders

  import Mox

  def create_handler(endpoint_url) do
    wellknown = %AuthProviders.WellKnown{
      authorization_endpoint: "#{endpoint_url}/authorization_endpoint",
      token_endpoint: "#{endpoint_url}/token_endpoint",
      userinfo_endpoint: "#{endpoint_url}/userinfo_endpoint"
    }

    handler_name = :crypto.strong_rand_bytes(6) |> Base.url_encode64()

    {:ok, handler} =
      AuthProviders.Handler.new(handler_name,
        wellknown: wellknown,
        client_id: "id",
        client_secret: "secret",
        redirect_uri: "http://localhost/callback_url"
      )

    {:ok, _} = AuthProviders.create_handler(handler)

    on_exit(fn -> AuthProviders.remove_handler(handler) end)

    handler
  end

  setup :verify_on_exit!

  setup do
    %{user: user_fixture()}
  end

  describe "GET /users/log_in" do
    test "renders log in page", %{conn: conn} do
      expect(Lightning.MockConfig, :check_flag?, fn _flag ->
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
      expect(Lightning.MockConfig, :check_flag?, fn _flag ->
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

    test "shows a 'via external provider' button", %{conn: conn} do
      create_handler("foo")

      conn = get(conn, Routes.user_session_path(conn, :new))
      response = html_response(conn, 200)
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
      expect(Lightning.MockConfig, :check_flag?, fn _flag ->
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
