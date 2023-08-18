defmodule LightningWeb.ReAuthenticateLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  setup :register_and_log_in_user

  describe "New" do
    setup %{conn: conn} do
      %{conn: put_session(conn, :user_return_to, "/return_here")}
    end

    test "load reauthentication page", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/auth/confirm_access")

      assert html =~ "Confirm access"
    end

    test "password is chosen by default", %{conn: conn} do
      {:ok, _live, html} = live(conn, ~p"/auth/confirm_access")

      assert html =~ "Confirm access"
      assert html =~ "Password"
      refute html =~ "Authentication Code"
    end

    test "user with mfa enabled sees the option to use authenticator app", %{
      conn: conn
    } do
      {:ok, _live, html} = live(conn, ~p"/auth/confirm_access")
      refute html =~ "Use your authenticator app instead"
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))

      conn = log_in_user(conn, user)
      {:ok, _live, html} = live(conn, ~p"/auth/confirm_access")
      assert html =~ "Use your authenticator app instead"
    end

    test "user can toggle the authentication method to use", %{
      conn: conn
    } do
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))

      conn = log_in_user(conn, user)

      {:ok, live, html} = live(conn, ~p"/auth/confirm_access")
      assert html =~ "Use your authenticator app instead"
      assert html =~ "Enter your password to confirm access"

      refute html =~ "Use your password instead"
      refute html =~ "Authentication Code"

      live |> element("#use-totp") |> render_click()
      html = render(live)

      refute html =~ "Use your authenticator app instead"
      refute html =~ "Enter your password to confirm access"

      assert html =~ "Use your password instead"
      assert html =~ "Authentication Code"
      assert html =~ "Open your two-factor authenticator (TOTP) app"

      live |> element("#use-password") |> render_click()
      html = render(live)

      assert html =~ "Use your authenticator app instead"
      assert html =~ "Enter your password to confirm access"

      refute html =~ "Use your password instead"
      refute html =~ "Authentication Code"
    end

    test "user can reauthenticate using the correct password", %{
      conn: conn
    } do
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))

      conn =
        conn |> log_in_user(user) |> put_session(:user_return_to, "/return_here")

      {:ok, live, _html} = live(conn, ~p"/auth/confirm_access")

      render_click(live, "toggle-option", %{"option" => "password"})

      {:error, _redirect} =
        live
        |> element("form#reauthentication-form")
        |> render_submit(user: %{password: user.password})

      user_token =
        Lightning.Repo.get_by!(Lightning.Accounts.UserToken,
          user_id: user.id,
          context: "sudo_session"
        )

      query_params =
        URI.encode_query(%{"sudo_token" => Base.encode64(user_token.token)})

      assert_redirected(
        live,
        "/return_here?#{query_params}"
      )
    end

    test "using an incorrect password shows an error", %{
      conn: conn
    } do
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))

      conn =
        conn |> log_in_user(user) |> put_session(:user_return_to, "/return_here")

      {:ok, live, _html} = live(conn, ~p"/auth/confirm_access")

      render_click(live, "toggle-option", %{"option" => "password"})

      refute render(live) =~ "Invalid password!. Try again"

      live
      |> element("form#reauthentication-form")
      |> render_submit(user: %{password: "wrong password"}) =~
        "Invalid password!. Try again"
    end

    test "user can reauthenticate using the correct totp code", %{
      conn: conn
    } do
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))

      conn =
        conn |> log_in_user(user) |> put_session(:user_return_to, "/return_here")

      {:ok, live, _html} = live(conn, ~p"/auth/confirm_access")

      render_click(live, "toggle-option", %{"option" => "totp"})

      correct_code = NimbleTOTP.verification_code(user.user_totp.secret)

      {:error, _redirect} =
        live
        |> element("form#reauthentication-form")
        |> render_submit(user: %{code: correct_code})

      user_token =
        Lightning.Repo.get_by!(Lightning.Accounts.UserToken,
          user_id: user.id,
          context: "sudo_session"
        )

      query_params =
        URI.encode_query(%{"sudo_token" => Base.encode64(user_token.token)})

      assert_redirected(
        live,
        "/return_here?#{query_params}"
      )
    end

    test "using an incorrect totp code shows an error", %{
      conn: conn
    } do
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))

      conn =
        conn |> log_in_user(user) |> put_session(:user_return_to, "/return_here")

      {:ok, live, _html} = live(conn, ~p"/auth/confirm_access")

      render_click(live, "toggle-option", %{"option" => "totp"})

      refute render(live) =~ "Invalid OTP code!. Try again"

      live
      |> element("form#reauthentication-form")
      |> render_submit(user: %{code: "wrongcode"}) =~
        "Invalid OTP code!. Try again"
    end
  end
end
