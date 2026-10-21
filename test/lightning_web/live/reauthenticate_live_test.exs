defmodule LightningWeb.ReAuthenticateLiveTest do
  use LightningWeb.ConnCase, async: true

  import Phoenix.LiveViewTest
  import Lightning.Factories

  setup :register_and_log_in_user

  # The page is drawn by React from data-props. Which method is on show, the
  # texts, the switch between password and code, and how a refusal is shown
  # are tested in the design system's AuthConfirmAccessPage.test.tsx; the
  # event it sends in assets/test/design-system/AuthConfirmAccessPage.test.tsx.
  @page "#auth-confirm-access-page"

  defp props(view), do: page_props(view, @page)

  defp confirm(view, user_params),
    do:
      push_page_event(view, @page, "reauthenticate-user", %{
        "user" => user_params
      })

  defp sudo_token(user) do
    Lightning.Repo.get_by(Lightning.Accounts.UserToken,
      user_id: user.id,
      context: "sudo_session"
    )
  end

  describe "New" do
    setup %{conn: conn} do
      %{conn: put_session(conn, :user_return_to, "/return_here")}
    end

    test "load reauthentication page", %{conn: conn, user: user} do
      {:ok, live, html} = live(conn, ~p"/auth/confirm_access")

      assert html =~ "Confirm access"
      # The :app layout has no sidebar, so the first paint draws none either.
      refute html =~ ~s(id="side-menu")

      assert %{
               "user" => %{
                 "firstName" => first_name,
                 "lastName" => last_name,
                 "mfaEnabled" => false
               }
             } = props(live)

      assert first_name == user.first_name
      assert last_name == user.last_name
    end

    test "user with mfa enabled gets the option to use the authenticator app", %{
      conn: conn
    } do
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))

      conn = log_in_user(conn, user)
      {:ok, live, _html} = live(conn, ~p"/auth/confirm_access")

      assert %{"user" => %{"mfaEnabled" => true}} = props(live)
    end

    test "user can reauthenticate using the correct password", %{
      conn: conn
    } do
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))

      conn =
        conn |> log_in_user(user) |> put_session(:user_return_to, "/return_here")

      {:ok, live, _html} = live(conn, ~p"/auth/confirm_access")

      confirm(live, %{"password" => user.password})

      user_token = sudo_token(user)
      assert user_token

      query_params =
        URI.encode_query(%{"sudo_token" => Base.encode64(user_token.token)})

      assert_redirected(live, "/return_here?#{query_params}")
    end

    test "using an incorrect password replies with the error and unlocks nothing",
         %{conn: conn} do
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))

      conn =
        conn |> log_in_user(user) |> put_session(:user_return_to, "/return_here")

      {:ok, live, _html} = live(conn, ~p"/auth/confirm_access")

      confirm(live, %{"password" => "wrong password"})

      assert_reply(live, %{error: "Invalid password! Try again."})
      refute sudo_token(user)
    end

    test "user can reauthenticate using the correct totp code", %{
      conn: conn
    } do
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))

      conn =
        conn |> log_in_user(user) |> put_session(:user_return_to, "/return_here")

      {:ok, live, _html} = live(conn, ~p"/auth/confirm_access")

      correct_code = NimbleTOTP.verification_code(user.user_totp.secret)

      confirm(live, %{"code" => correct_code})

      user_token = sudo_token(user)
      assert user_token

      query_params =
        URI.encode_query(%{"sudo_token" => Base.encode64(user_token.token)})

      assert_redirected(live, "/return_here?#{query_params}")
    end

    test "using an incorrect totp code replies with the error and unlocks nothing",
         %{conn: conn} do
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))

      conn =
        conn |> log_in_user(user) |> put_session(:user_return_to, "/return_here")

      {:ok, live, _html} = live(conn, ~p"/auth/confirm_access")

      confirm(live, %{"code" => "wrongcode"})

      assert_reply(live, %{error: "Invalid OTP code! Try again."})
      refute sudo_token(user)
    end

    test "a crafted event with neither a password nor a code is refused", %{
      conn: conn,
      user: user
    } do
      {:ok, live, _html} = live(conn, ~p"/auth/confirm_access")

      confirm(live, %{"backup_code" => "1234-5678"})

      assert_reply(live, %{error: _})
      refute sudo_token(user)
    end
  end
end
