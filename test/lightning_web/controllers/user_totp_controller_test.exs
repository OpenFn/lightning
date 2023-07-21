defmodule LightningWeb.UserTOTPControllerTest do
  use LightningWeb.ConnCase, async: false

  import Lightning.AccountsFixtures

  @totp_session :user_totp_pending

  setup %{conn: conn} do
    user = user_with_mfa_fixture()
    conn = conn |> log_in_user(user) |> put_session(@totp_session, true)
    %{user: user, conn: conn}
  end

  describe "GET /users/two-factor/app" do
    test "renders totp page", %{conn: conn} do
      conn = get(conn, Routes.user_totp_path(conn, :new))
      response = html_response(conn, 200)
      assert response =~ "Two-factor authentication"
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
             |> redirected_to() == "/"
    end
  end

  describe "POST /users/two-factor/app" do
    setup %{user: user, conn: conn} do
      %{user: user, conn: conn, totp: Lightning.Accounts.get_user_totp(user)}
    end

    test "validates totp correctly", %{conn: conn, totp: totp} do
      code = NimbleTOTP.verification_code(totp.secret)

      conn =
        post(conn, Routes.user_totp_path(conn, :create), %{
          "user" => %{"code" => code}
        })

      assert redirected_to(conn) == "/"
      assert get_session(conn, @totp_session) == nil
    end

    test "logs the user in with remember me", %{conn: conn, totp: totp} do
      code = NimbleTOTP.verification_code(totp.secret)

      conn =
        post(conn, Routes.user_totp_path(conn, :create), %{
          "user" => %{"code" => code, "remember_me" => "true"}
        })

      assert redirected_to(conn) == "/"
      assert get_session(conn, @totp_session) == nil
      assert conn.resp_cookies["_lightning_web_user_remember_me"]
    end

    test "logs the user in with return to", %{conn: conn, totp: totp} do
      code = NimbleTOTP.verification_code(totp.secret)

      conn =
        conn
        |> put_session(:user_return_to, "/return_here")
        |> post(Routes.user_totp_path(conn, :create), %{
          "user" => %{"code" => code}
        })

      assert redirected_to(conn) == "/return_here"
      assert get_session(conn, @totp_session) == nil
    end
  end
end
