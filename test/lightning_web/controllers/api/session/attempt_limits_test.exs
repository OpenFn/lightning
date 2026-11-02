defmodule LightningWeb.API.Session.AttemptLimitsTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import Lightning.Factories

  alias Lightning.Accounts

  @password "hello world!"
  @session_challenge [~s(Session realm="Lightning")]

  defp mfa_user do
    insert(:user,
      mfa_enabled: true,
      user_totp: build(:user_totp),
      backup_codes: build_list(10, :backup_code)
    )
  end

  defp totp(user), do: NimbleTOTP.verification_code(user.user_totp.secret)

  defp sign_in(conn, body),
    do: post(conn, ~p"/api/session", Jason.encode!(body))

  defp fail_sign_ins(user, times) do
    for _attempt <- 1..times do
      build_conn()
      |> from_own_page()
      |> sign_in(%{email: user.email, password: "not the password"})
      |> assert_unauthenticated(:invalid_credentials, @session_challenge)
    end
  end

  test "after ten failed sign-ins an account refuses every attempt, the right password too" do
    user = insert(:user)
    fail_sign_ins(user, 10)

    conn =
      build_conn()
      |> from_own_page()
      |> sign_in(%{email: String.upcase(user.email), password: @password})

    assert_problem(conn, 429, :too_many_requests, [])
    assert get_resp_header(conn, "set-cookie") == []
  end

  test "stepping up and finishing an MFA sign-in count against the same limit" do
    user = mfa_user()
    fail_sign_ins(user, 10)

    for {conn, body} <- [
          {session_conn(build_conn(), user), %{password: @password}},
          {session_conn(build_conn(), user, mfa_pending: true),
           %{mfa_code: totp(user)}}
        ] do
      conn |> sign_in(body) |> assert_problem(429, :too_many_requests, [])
    end
  end

  test "a pending MFA sign-in that fails five codes is ended, so the password is needed again" do
    user = mfa_user()
    conn = session_conn(build_conn(), user, mfa_pending: true)

    for _attempt <- 1..5 do
      conn
      |> sign_in(%{mfa_code: "000000"})
      |> assert_unauthenticated(:invalid_credentials, @session_challenge)
    end

    refute Accounts.get_user_by_session_token(get_session(conn, :user_token))

    conn
    |> sign_in(%{mfa_code: totp(user)})
    |> assert_unauthenticated(:unauthenticated, @session_challenge)
  end
end
