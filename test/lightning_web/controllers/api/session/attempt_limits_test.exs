defmodule LightningWeb.API.Session.AttemptLimitsTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import Lightning.Factories
  import Lightning.SignInAttemptHelpers, only: [assert_retry_after: 1]

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

  defp assert_limited(conn) do
    assert_problem(conn, 429, :too_many_requests, [])
    assert_retry_after(conn)
  end

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

    assert_limited(conn)
    assert get_resp_header(conn, "set-cookie") == []
  end

  test "an empty password counts as a failed sign-in" do
    user = insert(:user)

    for _attempt <- 1..10 do
      build_conn()
      |> from_own_page()
      |> sign_in(%{email: user.email, password: ""})
      |> assert_unauthenticated(:invalid_credentials, @session_challenge)
    end

    build_conn()
    |> from_own_page()
    |> sign_in(%{email: user.email, password: @password})
    |> assert_limited()
  end

  test "failures on the log-in page count against the same limit" do
    user = insert(:user)

    for _attempt <- 1..10 do
      post(build_conn(), ~p"/users/log_in", %{
        "user" => %{"email" => user.email, "password" => "not the password"}
      })
    end

    build_conn()
    |> from_own_page()
    |> sign_in(%{email: user.email, password: @password})
    |> assert_limited()
  end

  test "finishing an MFA sign-in counts against the same limit" do
    user = mfa_user()
    fail_sign_ins(user, 10)

    build_conn()
    |> session_conn(user, mfa_pending: true)
    |> sign_in(%{mfa_code: totp(user)})
    |> assert_limited()
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
