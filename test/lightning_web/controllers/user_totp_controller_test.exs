defmodule LightningWeb.UserTOTPControllerTest do
  use LightningWeb.ConnCase, async: false

  import Lightning.Factories

  @totp_session :user_totp_pending

  setup %{conn: conn} do
    user =
      insert(:user,
        mfa_enabled: true,
        user_totp: build(:user_totp),
        backup_codes: build_list(10, :backup_code)
      )

    conn = conn |> log_in_user(user) |> put_session(@totp_session, true)
    %{user: user, conn: conn}
  end

  describe "GET /users/two-factor" do
    test "renders totp page by default", %{conn: conn} do
      conn = get(conn, Routes.user_totp_path(conn, :new))
      response = html_response(conn, 200)
      assert response =~ "Two-factor authentication"

      assert response =~
               "Open your two-factor authenticator (TOTP) app or browser extension to view your authentication code"

      refute response =~ "Use one of your backup codes"
    end

    test "renders backup code page by default", %{conn: conn} do
      conn =
        get(
          conn,
          Routes.user_totp_path(conn, :new, authentication_type: "backup_code")
        )

      response = html_response(conn, 200)
      assert response =~ "Two-factor authentication"

      refute response =~
               "Open your two-factor authenticator (TOTP) app or browser extension to view your authentication code"

      assert response =~ "Use one of your backup codes"
    end

    test "reads remember me from URL", %{conn: conn} do
      conn =
        get(conn, Routes.user_totp_path(conn, :new), user: [remember_me: "true"])

      response = html_response(conn, 200)

      assert response =~
               ~s|<input id="user_remember_me" name="user[remember_me]" type="hidden" value="true">|
    end

    test "redirects to login if not logged in" do
      conn = build_conn()

      assert conn
             |> get(Routes.user_totp_path(conn, :new))
             |> redirected_to() ==
               Routes.user_session_path(conn, :new)
    end

    test "redirects to dashboard if totp is not pending", %{conn: conn} do
      assert conn
             |> delete_session(@totp_session)
             |> get(Routes.user_totp_path(conn, :new))
             |> redirected_to() == "/projects"
    end
  end

  describe "POST /users/two-factor using app" do
    test "validates totp correctly", %{conn: conn, user: user} do
      code = NimbleTOTP.verification_code(user.user_totp.secret)

      conn =
        post(conn, Routes.user_totp_path(conn, :create), %{
          "user" => %{"code" => code, "authentication_type" => "totp"}
        })

      assert redirected_to(conn) == "/projects"
      assert get_session(conn, @totp_session) == nil
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      code = NimbleTOTP.verification_code(user.user_totp.secret)

      conn =
        post(conn, Routes.user_totp_path(conn, :create), %{
          "user" => %{
            "code" => code,
            "authentication_type" => "totp",
            "remember_me" => "true"
          }
        })

      assert redirected_to(conn) == "/projects"
      assert get_session(conn, @totp_session) == nil
      assert conn.resp_cookies["_lightning_web_user_remember_me"]
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      code = NimbleTOTP.verification_code(user.user_totp.secret)

      conn =
        conn
        |> put_session(:user_return_to, "/return_here")
        |> post(Routes.user_totp_path(conn, :create), %{
          "user" => %{"code" => code, "authentication_type" => "totp"}
        })

      assert redirected_to(conn) == "/return_here"
      assert get_session(conn, @totp_session) == nil
    end
  end

  describe "POST /users/two-factor using backup code" do
    test "validates the backup code correctly", %{conn: conn, user: user} do
      backup_code = Enum.random(user.backup_codes)

      conn =
        post(conn, Routes.user_totp_path(conn, :create), %{
          "user" => %{
            "code" => "wrong code",
            "authentication_type" => "backup_code"
          }
        })

      response = html_response(conn, 200)
      assert response =~ "Invalid two-factor authentication code"
      refute get_session(conn, @totp_session) == nil

      conn =
        post(conn, Routes.user_totp_path(conn, :create), %{
          "user" => %{
            "code" => backup_code.code,
            "authentication_type" => "backup_code"
          }
        })

      assert redirected_to(conn) == "/projects"
      assert get_session(conn, @totp_session) == nil
    end

    test "logs the user in with remember me", %{conn: conn, user: user} do
      backup_code = Enum.random(user.backup_codes)

      conn =
        post(conn, Routes.user_totp_path(conn, :create), %{
          "user" => %{
            "code" => backup_code.code,
            "authentication_type" => "backup_code",
            "remember_me" => "true"
          }
        })

      assert redirected_to(conn) == "/projects"
      assert get_session(conn, @totp_session) == nil
      assert conn.resp_cookies["_lightning_web_user_remember_me"]
    end

    test "logs the user in with return to", %{conn: conn, user: user} do
      backup_code = Enum.random(user.backup_codes)

      conn =
        conn
        |> put_session(:user_return_to, "/return_here")
        |> post(Routes.user_totp_path(conn, :create), %{
          "user" => %{
            "code" => backup_code.code,
            "authentication_type" => "backup_code"
          }
        })

      assert redirected_to(conn) == "/return_here"
      assert get_session(conn, @totp_session) == nil
    end
  end
end
