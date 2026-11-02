defmodule LightningWeb.API.SessionController do
  @moduledoc """
  Signing in and out of Lightning's own app, which then calls the API with the
  session token (`LightningWeb.SessionToken`). Every action answers only
  requests from Lightning's own pages.

  `POST /api/session` with `email` and `password` signs in, replacing any
  session the request carried, and answers 201 with the session. When the
  account has MFA and the body has no `mfa_code` or `backup_code`, it answers
  401 `mfa_required` and sets a session that can only send the code: a second
  `POST` with just `mfa_code` or `backup_code` finishes signing in. Signed in,
  a `POST` with `password` or `mfa_code` steps the session up for five minutes.
  Every refused sign-in or step-up is the same 401 `invalid_credentials`,
  whether the email is unknown, the password or code is wrong, or the account
  is disabled or scheduled for deletion. A `POST` that names another origin is
  403 `forbidden`, so another site can't sign a browser in.

  `GET /api/session` reads the session, with a CSRF token for writes, and
  answers 401 without one. `DELETE /api/session` signs out and answers 204
  whether or not there was a session.

  A `POST` or `DELETE` that rides on an existing session needs its
  `x-csrf-token`; signing in with an email doesn't, since it starts a new one.
  """
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Problem
  alias LightningWeb.API.Request
  alias LightningWeb.Auth
  alias LightningWeb.SessionToken
  alias LightningWeb.UserAuth

  action_fallback FallbackController

  @fields ~w(email password mfa_code backup_code)a

  def create(conn, _params) do
    body = conn.body_params

    with :ok <- own_page(conn) do
      if is_map_key(body, "email"),
        do: sign_in(conn, body),
        else: continue_session(conn, body)
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
      {nil, conn} ->
        send_resp(conn, 204, "")

      {_session, conn} ->
        with :ok <- SessionToken.check_csrf(conn) do
          conn |> UserAuth.end_session() |> send_resp(204, "")
        end
    end
  end

  defp own_page(conn) do
    if SessionToken.from_own_page?(conn),
      do: :ok,
      else: {:error, :forbidden}
  end

  defp sign_in(conn, body) do
    with :ok <- Request.check_object(body),
         :ok <- check_body(body, required: [:email, :password]),
         {:ok, user} <- authenticate(body["email"], body["password"]) do
      cond do
        not user.mfa_enabled ->
          conn |> fetch_session() |> UserAuth.log_in_user(user) |> signed_in()

        code_sent?(body) ->
          with :ok <- check_code(user, body) do
            conn |> fetch_session() |> UserAuth.log_in_user(user) |> signed_in()
          end

        true ->
          # The session is set on this answer, so it is sent here rather than
          # returned to the fallback, which answers the conn it was handed.
          conn
          |> fetch_session()
          |> UserAuth.log_in_user(user)
          |> UserAuth.mark_totp_pending()
          |> Problem.respond(Auth.session_problem(:mfa_required))
      end
    end
  end

  defp continue_session(conn, body) do
    case SessionToken.read(conn) do
      {%{state: :signed_in, user: user}, conn} ->
        with :ok <- SessionToken.check_csrf(conn),
             :ok <- Request.check_object(body),
             :ok <- check_step_up_body(body),
             :ok <- check_step_up(user, body) do
          conn |> UserAuth.step_up(user) |> signed_in()
        end

      {%{state: :mfa_required, user: user}, conn} ->
        with :ok <- SessionToken.check_csrf(conn),
             :ok <- Request.check_object(body),
             :ok <- check_code_body(body),
             :ok <- check_code(user, body) do
          conn |> UserAuth.totp_validated() |> signed_in()
        end

      {_none_or_shut_out, _conn} ->
        with :ok <- Request.check_object(body) do
          check_body(body, required: [:email, :password])
        end
    end
  end

  defp authenticate(email, password) do
    with %User{} = user <-
           Accounts.get_user_by_email_and_password(email, password),
         false <- Accounts.login_blocked?(user) do
      {:ok, user}
    else
      _refused -> invalid_credentials()
    end
  end

  defp check_step_up(user, %{"password" => password}) do
    if User.valid_password?(user, password), do: :ok, else: invalid_credentials()
  end

  defp check_step_up(user, %{"mfa_code" => _code} = body),
    do: check_code(user, body)

  defp check_code(%User{mfa_enabled: true} = user, %{"mfa_code" => code}),
    do:
      if(Accounts.valid_user_totp?(user, code),
        do: :ok,
        else: invalid_credentials()
      )

  defp check_code(%User{mfa_enabled: true} = user, %{"backup_code" => code}),
    do:
      if(Accounts.valid_user_backup_code?(user, code),
        do: :ok,
        else: invalid_credentials()
      )

  defp check_code(_user, _body), do: invalid_credentials()

  defp invalid_credentials,
    do: {:error, Auth.session_problem(:invalid_credentials)}

  defp code_sent?(body),
    do: is_map_key(body, "mfa_code") or is_map_key(body, "backup_code")

  defp check_code_body(body) do
    body
    |> entries(required: [])
    |> Kernel.++(code_entries(body, :mfa_code))
    |> Errors.refuse()
  end

  defp check_step_up_body(body) do
    extra =
      cond do
        is_map_key(body, "backup_code") ->
          [
            Errors.entry(
              ["backup_code"],
              {"can't be used to step up", code: :not_allowed}
            )
          ]

        is_map_key(body, "password") and is_map_key(body, "mfa_code") ->
          [exclusive("mfa_code", "password")]

        is_map_key(body, "password") or is_map_key(body, "mfa_code") ->
          []

        true ->
          [Errors.entry(["password"], {"can't be blank", code: :required})]
      end

    body |> entries(required: []) |> Kernel.++(extra) |> Errors.refuse()
  end

  defp check_body(body, required: required) do
    body
    |> entries(required: required)
    |> Kernel.++(if code_sent?(body), do: code_entries(body, nil), else: [])
    |> Errors.refuse()
  end

  # `mfa_code` and `backup_code` are alternatives; `required` names the one to
  # point at when neither is sent, or nil when neither is needed.
  defp code_entries(body, required) do
    cond do
      is_map_key(body, "mfa_code") and is_map_key(body, "backup_code") ->
        [exclusive("backup_code", "mfa_code")]

      code_sent?(body) or is_nil(required) ->
        []

      true ->
        [
          Errors.entry(
            [Atom.to_string(required)],
            {"can't be blank", code: :required}
          )
        ]
    end
  end

  defp exclusive(key, other),
    do:
      Errors.entry(
        [key],
        {"can't be sent with %{other}", code: :exclusive, other: other}
      )

  defp entries(body, required: required) do
    missing =
      for field <- required,
          not is_map_key(body, Atom.to_string(field)),
          do:
            Errors.entry(
              [Atom.to_string(field)],
              {"can't be blank", code: :required}
            )

    not_strings =
      for key <- Enum.map(@fields, &Atom.to_string/1),
          is_map_key(body, key),
          not is_binary(body[key]),
          do: Errors.entry([key], {"is invalid", code: :type})

    Request.unknown_keys(body, [], @fields) ++ missing ++ not_strings
  end

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
