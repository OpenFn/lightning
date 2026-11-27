defmodule LightningWeb.API.SessionController do
  @moduledoc """
  Signing in and out of Lightning's own app, which then calls the API with the
  session token (`LightningWeb.SessionToken`). Every action answers only
  requests from Lightning's own pages.

  `POST /api/session` with `email` and `password` signs in, replacing any
  session the request carried, and answers 201 with the session. When the
  account has MFA and the body has no `mfa_code` or `backup_code`, it answers
  401 `mfa_required` and sets a session that can only send the code: a second
  `POST` with just `mfa_code` or `backup_code` finishes signing in. Every
  refused sign-in is the same 401 `invalid_credentials`, whether the email is
  unknown, the password or code is wrong, or the account is disabled or
  scheduled for deletion. A `POST` that names another origin is 403
  `forbidden`, so another site can't sign a browser in.

  Failed passwords and codes are limited per account
  (`Lightning.Accounts.SignInAttempts`): once an account has failed too often,
  every attempt on it, right or wrong, is 429 `too_many_requests` until the
  window ends, with a `retry-after` header giving the seconds left, and a
  pending MFA sign-in that fails five codes is ended, so the password has to be
  entered again. A `POST` with only a code and no pending sign-in to continue is
  401 `unauthenticated`.

  `GET /api/session` reads the session, with a CSRF token for writes, and
  answers 401 without one. `DELETE /api/session` signs out and answers 204
  whether or not there was a session. It ends whatever session the request
  carries, even one whose account may no longer sign in, so the session stays
  ended if the account is allowed back, and it hangs up the person's open
  connections on every device, channels as well as LiveView pages; the other
  devices reconnect on their own sessions. Logging out of the LiveView pages
  hangs up only the pages. Ending a sign-in that is still waiting for its MFA
  code hangs up nothing.

  A `POST` that finishes a pending sign-in and a `DELETE` ride on an existing
  session, so they need its `x-csrf-token`; signing in with an email doesn't,
  since it starts a new one.
  Signing out of a session that is no longer usable needs it only when the
  session holds CSRF state, since without it the app has no way to get one.
  """
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias Lightning.Accounts.SignInAttempts
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Problem
  alias LightningWeb.API.SessionParams
  alias LightningWeb.Auth
  alias LightningWeb.SessionToken
  alias LightningWeb.UserAuth

  action_fallback FallbackController

  def create(conn, _params) do
    with :ok <- own_page(conn) do
      case conn.body_params do
        %{"email" => _} = body -> sign_in(conn, body)
        body -> continue_session(conn, body)
      end
    end
  end

  def show(conn, _params) do
    case SessionToken.read(conn) do
      {nil, _conn} -> {:error, Auth.session_problem(:unauthenticated)}
      {session, conn} -> respond(conn, 200, session)
    end
  end

  def delete(conn, _params) do
    case SessionToken.read(conn) do
      {session, conn} when is_map(session) ->
        with :ok <- SessionToken.check_csrf(conn) do
          conn = UserAuth.end_session(conn)
          hang_up_sockets(session)
          send_resp(conn, 204, "")
        end

      {nil, conn} ->
        if SessionToken.unusable_session?(conn),
          do: end_unusable_session(conn),
          else: send_resp(conn, 204, "")
    end
  end

  # A sign-in still waiting for its MFA code has proved only the password, so
  # ending it must not reach the person's connections on other devices.
  defp hang_up_sockets(%{state: :mfa_required}), do: :ok
  defp hang_up_sockets(%{user: user}), do: UserAuth.disconnect_user_sockets(user)

  # The session names a token `read/1` found no person for: revoked, expired,
  # or its account disabled or scheduled for deletion. Ending it still revokes
  # the token and clears the cookies, so an account that is allowed back isn't
  # signed in again on this browser.
  defp end_unusable_session(conn) do
    with :ok <- check_csrf_if_held(conn) do
      conn |> UserAuth.end_session() |> send_resp(204, "")
    end
  end

  defp check_csrf_if_held(conn) do
    if SessionToken.holds_csrf_state?(conn),
      do: SessionToken.check_csrf(conn),
      else: :ok
  end

  defp own_page(conn) do
    if SessionToken.from_own_page?(conn),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp sign_in(conn, body) do
    with {:ok, %{email: email, password: password, code: code}} <-
           SessionParams.sign_in(body),
         {:ok, user} <- authenticate(email, password) do
      cond do
        not user.mfa_enabled ->
          conn |> fetch_session() |> UserAuth.log_in_user(user) |> signed_in()

        code ->
          with :ok <- refuse_code(SignInAttempts.check_code(user, code)) do
            conn |> fetch_session() |> UserAuth.log_in_user(user) |> signed_in()
          end

        true ->
          # The session is set on this answer, so it is sent here rather than
          # returned to the fallback, which answers the conn it was handed.
          conn
          |> fetch_session()
          |> UserAuth.log_in_user(user)
          |> UserAuth.mark_totp_pending()
          |> put_resp_header("cache-control", "no-store")
          |> Problem.respond(Auth.session_problem(:mfa_required))
      end
    end
  end

  defp continue_session(conn, body) do
    case SessionToken.read(conn) do
      {%{state: :mfa_required, user: user}, conn} ->
        with :ok <- SessionToken.check_csrf(conn),
             {:ok, code} <- SessionParams.continuation(body),
             do: finish_pending(conn, user, code)

      # A code with no email finishes a pending sign-in, so without one it is
      # missing its authentication, not a field: a client whose pending
      # sign-in lapsed mid-flow hears 401, as any route does. Any other body
      # is a sign-in that forgot its email.
      {_nothing_pending, _conn} ->
        if is_map_key(body, "mfa_code") or is_map_key(body, "backup_code"),
          do: {:error, Auth.session_problem(:unauthenticated)},
          else: sign_in(conn, body)
    end
  end

  # After the last try fails the sign-in is ended, so the password has to be
  # entered again. The session is cleared on that answer, so it is sent here
  # rather than returned to the fallback.
  defp finish_pending(conn, user, code) do
    token = get_session(conn, :user_token)

    case SignInAttempts.check_code(user, code, token) do
      :ok ->
        conn |> UserAuth.totp_validated() |> signed_in()

      {:error, :tries_spent} ->
        conn
        |> UserAuth.end_session()
        |> Problem.respond(Auth.session_problem(:invalid_credentials))

      refused ->
        refuse_code(refused)
    end
  end

  defp authenticate(email, password) do
    case SignInAttempts.check_password(email, password) do
      {:ok, user} ->
        if Accounts.login_blocked?(user),
          do: invalid_credentials(),
          else: {:ok, user}

      {:error, {:rate_limited, _seconds}} = limited ->
        limited

      {:error, :invalid_credentials} ->
        invalid_credentials()
    end
  end

  defp refuse_code(:ok), do: :ok
  defp refuse_code({:error, {:rate_limited, _seconds}} = limited), do: limited
  defp refuse_code({:error, :invalid_credentials}), do: invalid_credentials()

  defp invalid_credentials,
    do: {:error, Auth.session_problem(:invalid_credentials)}

  defp signed_in(conn) do
    {session, conn} = SessionToken.read(conn)
    respond(conn, 201, session)
  end

  defp respond(conn, status, session) do
    {csrf_token, conn} = SessionToken.csrf_token(conn)

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(status)
    |> render(:show, session: session, csrf_token: csrf_token)
  end
end
