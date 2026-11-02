defmodule LightningWeb.API.MeMfaController do
  @moduledoc """
  The signed-in person's MFA, on a session token only, since changing how a
  person proves who they are needs that person at the keyboard. Any other token
  is 403 `forbidden`.

  The settings are `{"enabled", "backup_codes"}`. `backup_codes` lists every
  code with when it was used, but only to a session stepped up in the last five
  minutes; otherwise it is `null`.

  `GET /api/me/mfa` reads them.

  `POST /api/me/mfa` starts setting up, or replacing, an authenticator. It
  saves nothing and answers 201 with a new `secret`, base32 encoded, and its
  `otpauth_uri` to show as a QR code.

  `PUT /api/me/mfa` takes that `secret` and a `code` from the authenticator,
  saves the secret in place of any old one, and answers 200 with the settings.
  When MFA was off, it turns it on, makes ten backup codes if the person has
  none, and steps the session up so the app can show them. A code that doesn't
  match the secret is 422 with a `mismatch` entry at `#/code`; a secret
  `POST /api/me/mfa` couldn't have given is a `format` entry at `#/secret`.

  `DELETE /api/me/mfa` turns MFA off and answers 204, even when it was already
  off. It keeps the backup codes, so turning MFA on again makes no new ones.
  It needs a stepped-up session, as `POST /api/me/mfa/backup_codes` does, which
  replaces every backup code at once and answers 201 with the settings. A
  session that hasn't stepped up is 403 `step_up_required`, and making backup
  codes without MFA on is 403 `forbidden`.

  A write that loses a race with another request turning MFA off, or making
  new backup codes, is 409 `concurrent_edit`.
  """
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.Accounts.UserTOTP
  alias Lightning.Scope
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Request
  alias LightningWeb.Plugs.AuthorizeAction
  alias LightningWeb.UserAuth

  action_fallback FallbackController

  @issuer "OpenFn"
  # NimbleTOTP's secrets are 20 bytes, which base32 writes in 32 characters.
  @secret_bytes 20

  plug AuthorizeAction, {:account, :read_own_mfa} when action == :show
  plug AuthorizeAction, {:account, :start_mfa} when action == :create
  plug AuthorizeAction, {:account, :enable_mfa} when action == :update
  plug AuthorizeAction, {:account, :disable_mfa} when action == :delete

  plug AuthorizeAction,
       {:account, :regenerate_backup_codes}
       when action == :create_backup_codes

  def show(conn, _params) do
    %Scope{actor: user} = scope = conn.assigns.scope
    settings(conn, user, Scope.stepped_up?(scope))
  end

  def create(conn, _params) do
    %Scope{actor: user} = conn.assigns.scope
    secret = totp_client().secret()

    conn
    |> put_resp_header("cache-control", "no-store")
    |> put_status(:created)
    |> json(%{
      data: %{
        secret: Base.encode32(secret, padding: false),
        otpauth_uri:
          NimbleTOTP.otpauth_uri("#{@issuer}:#{user.email}", secret,
            issuer: @issuer
          )
      }
    })
  end

  def update(conn, _params) do
    %Scope{actor: user} = scope = conn.assigns.scope
    body = conn.body_params

    with :ok <- Request.check_object(body),
         {:ok, secret} <- check_body(body),
         {:ok, _totp} <- save_totp(user, secret, body["code"]) do
      if user.mfa_enabled do
        settings(conn, %{user | mfa_enabled: true}, Scope.stepped_up?(scope))
      else
        conn
        |> UserAuth.step_up(user)
        |> settings(%{user | mfa_enabled: true}, true)
      end
    end
  end

  def delete(conn, _params) do
    %Scope{actor: user} = conn.assigns.scope

    case Accounts.get_user_totp(user) do
      nil ->
        send_resp(conn, 204, "")

      totp ->
        with {:ok, _totp} <- Accounts.delete_user_totp(totp) do
          send_resp(conn, 204, "")
        end
    end
  end

  def create_backup_codes(conn, _params) do
    %Scope{actor: user} = conn.assigns.scope

    with {:ok, _user} <- Accounts.regenerate_user_backup_codes(user) do
      conn
      |> put_status(:created)
      |> settings(user, true)
    end
  end

  defp settings(conn, %User{} = user, stepped_up?) do
    backup_codes =
      if stepped_up? do
        for code <- Accounts.list_user_backup_codes(user),
            do: %{code: code.code, used_at: code.used_at}
      end

    conn
    |> put_resp_header("cache-control", "no-store")
    |> json(%{data: %{enabled: user.mfa_enabled, backup_codes: backup_codes}})
  end

  defp save_totp(user, secret, code) do
    totp = Accounts.get_user_totp(user) || %UserTOTP{user_id: user.id}
    Accounts.upsert_user_totp(%{totp | secret: secret}, %{code: code})
  end

  # The secret is checked here; the code by the changeset, against it. A
  # problem with either comes back with every other problem in the body.
  defp check_body(body) do
    {secret, secret_entries} = secret(body)

    code_entries =
      case body do
        %{"code" => code} when is_binary(code) -> []
        %{"code" => _other} -> [type_entry("code")]
        _missing -> [required_entry("code")]
      end

    case Request.unknown_keys(body, [], [:secret, :code]) ++
           secret_entries ++ code_entries do
      [] -> {:ok, secret}
      entries -> Errors.refuse(entries)
    end
  end

  defp secret(%{"secret" => secret}) when is_binary(secret) do
    case Base.decode32(String.upcase(secret), padding: false) do
      {:ok, <<_::binary-size(@secret_bytes)>> = decoded} ->
        {decoded, []}

      _other ->
        {nil,
         [
           Errors.entry(
             ["secret"],
             {"is not a secret POST /api/me/mfa gives", code: :format}
           )
         ]}
    end
  end

  defp secret(%{"secret" => _other}), do: {nil, [type_entry("secret")]}
  defp secret(_body), do: {nil, [required_entry("secret")]}

  defp type_entry(key), do: Errors.entry([key], {"is invalid", code: :type})

  defp required_entry(key),
    do: Errors.entry([key], {"can't be blank", code: :required})

  # The account page reads the same setting, so tests can make a secret to
  # build a matching code from.
  defp totp_client, do: Application.get_env(:lightning, :totp_client, NimbleTOTP)
end
