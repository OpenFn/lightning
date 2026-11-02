defmodule LightningWeb.API.ConfirmationController do
  @moduledoc """
  The links Lightning emails to confirm a new account, a new email address or
  a credential transfer.

  `POST /api/confirmations` sends the account confirmation email again. With
  `{"email": "…"}` it takes no token and answers 202 with no body whether or
  not an account has the email, or still needs confirming, so it can't be used
  to find accounts. With no email it is for the signed-in person, on a session
  token from Lightning's own pages, including one shut out until the account
  is confirmed: 202 once the email is sent (or straight away when the account
  is already confirmed, since there is nothing to send), 429
  `too_many_requests` after three in 15 minutes, and 503 `service_unavailable`
  when it can't be sent. With neither, it is 422 with a `required` entry at
  `#/email`.

  `PUT /api/confirmations/:token` confirms what the token is for, on the
  session token of the person it was sent to, shut out or not: the account,
  a new email address (which then replaces the old one), or a credential
  transfer (which then moves the credential to its recipient). It answers 200
  with which it confirmed. Each token works once, and a used, expired or
  unknown token, or one sent to someone else, is 404 `not_found`, as is one
  another request used while this one was confirming with it. Without a
  session it is 401 `unauthenticated`. It takes no body, and ignores one.

  A write on a session needs the session's `x-csrf-token`.
  """
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Credentials
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Problem
  alias LightningWeb.API.Request
  alias LightningWeb.Auth
  alias LightningWeb.SessionToken

  require Logger

  action_fallback FallbackController

  # Both may use a session whose account is shut out until it is confirmed;
  # confirming it is how they get back in.
  @session_states [:signed_in, :confirmation_required]

  def create(conn, _params) do
    body = conn.body_params

    with :ok <- Request.check_object(body) do
      if is_map_key(body, "email"),
        do: resend_by_email(conn, body),
        else: resend_to_session(conn, body)
    end
  end

  def update(conn, %{"token" => token}) do
    with {:ok, user, conn} <- session(conn),
         :ok <- SessionToken.check_csrf(conn),
         {:ok, kind} <- confirm(user, token) do
      json(conn, %{data: %{confirmed: kind}})
    end
  end

  defp resend_by_email(conn, body) do
    with :ok <- check_body(body, email_entries(body)) do
      if user = Accounts.get_user_by_email(body["email"]) do
        # Already confirmed, or sent too often: the answer is the same, so
        # it says nothing about the account.
        Accounts.deliver_user_confirmation_instructions(user)
      end

      send_resp(conn, 202, "")
    end
  end

  defp resend_to_session(conn, body) do
    case session(conn) do
      {:ok, user, conn} ->
        with :ok <- SessionToken.check_csrf(conn),
             :ok <- check_body(body, []),
             :ok <- remind(user) do
          send_resp(conn, 202, "")
        end

      {:error, _no_session} ->
        check_body(body, email_entries(body))
    end
  end

  defp remind(%User{confirmed_at: %DateTime{}}), do: :ok

  defp remind(user) do
    case Accounts.remind_account_confirmation(user) do
      {:ok, _email} ->
        :ok

      {:error, :rate_limited} = limited ->
        limited

      {:error, reason} ->
        Logger.warning(
          "Could not resend an account confirmation email: #{inspect(reason)}"
        )

        {:error, Problem.new(:service_unavailable)}
    end
  end

  defp session(conn) do
    case SessionToken.read(conn) do
      {%{state: state, user: user}, conn} when state in @session_states ->
        {:ok, user, conn}

      {_none, _conn} ->
        {:error, Auth.session_problem(:unauthenticated)}
    end
  end

  # The tokens don't say what they are for, so each kind is tried in turn.
  # An account token counts only for the person it was sent to; an email
  # change token is only looked for among the person's own, and a transfer
  # token only confirms for the credential's owner.
  defp confirm(%User{id: user_id} = user, token) do
    with :error <- confirm_account(user_id, token),
         :error <- confirm_email(user, token),
         :error <- confirm_transfer(user, token) do
      {:error, :not_found}
    end
  end

  defp confirm_account(user_id, token) do
    with %User{id: ^user_id} <- Accounts.get_user_by_confirmation_token(token),
         {:ok, _user} <- Accounts.confirm_user(token) do
      {:ok, :account}
    else
      _not_theirs_or_spent -> :error
    end
  end

  defp confirm_email(user, token) do
    case Accounts.update_user_email(user, token) do
      {:ok, _user} -> {:ok, :email}
      :error -> :error
    end
  end

  defp confirm_transfer(user, token) do
    case Credentials.confirm_transfer(token, user) do
      {:ok, _credential} -> {:ok, :credential_transfer}
      {:error, _reason} -> :error
    end
  end

  defp email_entries(%{"email" => email}) when is_binary(email), do: []

  defp email_entries(%{"email" => _not_a_string}),
    do: [Errors.entry(["email"], {"is invalid", code: :type})]

  defp email_entries(_body),
    do: [Errors.entry(["email"], {"can't be blank", code: :required})]

  defp check_body(body, entries),
    do: Errors.refuse(Request.unknown_keys(body, [], [:email]) ++ entries)
end
