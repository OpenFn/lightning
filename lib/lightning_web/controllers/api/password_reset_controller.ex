defmodule LightningWeb.API.PasswordResetController do
  @moduledoc """
  Resetting a forgotten password. Both actions take no token, so they work for
  anyone, signed in or not.

  `POST /api/password_resets` takes `{"email": "…"}`. If an account has the
  email, Lightning emails it a link to the reset page. It answers 202 with no
  body whether or not an account has the email, so it can't be used to find
  accounts.

  `PUT /api/password_resets/:token` takes `{"password": "…"}` and sets the
  password of the account the emailed token was made for. The token works
  once, for a day; a used, expired or unknown one is 404 `not_found`. Setting
  the password revokes every token the person holds, sessions and personal
  access tokens alike, and hangs up their sockets, and it doesn't sign them in,
  so a leaked link can't open the account. It answers 204 with no body. Two
  requests carrying one token can't both set a password: the one that loses
  the race is 409 `concurrent_edit`.

  Each answers 400 `malformed` to a body that isn't a JSON object, and 422
  `invalid` naming every problem with one that is, an unknown key among them.
  """
  use LightningWeb, :controller

  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias LightningWeb.API.Errors
  alias LightningWeb.API.FallbackController
  alias LightningWeb.API.Request

  action_fallback FallbackController

  def create(conn, _params) do
    body = conn.body_params

    with :ok <- Request.check_object(body),
         :ok <- check_email(body) do
      if user = Accounts.get_user_by_email(body["email"]) do
        Accounts.deliver_user_reset_password_instructions(
          user,
          &url(~p"/users/reset_password/#{&1}")
        )
      end

      send_resp(conn, 202, "")
    end
  end

  def update(conn, %{"token" => token}) do
    body = conn.body_params
    attrs = Map.take(body, ["password"])

    with {:ok, user} <- fetch_user(token),
         :ok <- Request.check_object(body),
         :ok <- check_password(body, user, attrs),
         {:ok, _user} <- Accounts.reset_user_password(user, attrs, token) do
      send_resp(conn, 204, "")
    end
  end

  defp fetch_user(token) do
    case Accounts.get_user_by_reset_password_token(token) do
      %User{} = user -> {:ok, user}
      nil -> {:error, :not_found}
    end
  end

  defp check_email(body) do
    email =
      case body do
        %{"email" => email} when is_binary(email) ->
          []

        %{"email" => _not_a_string} ->
          [Errors.entry(["email"], {"is invalid", code: :type})]

        _missing ->
          [Errors.entry(["email"], {"can't be blank", code: :required})]
      end

    Errors.refuse(Request.unknown_keys(body, [], [:email]) ++ email)
  end

  # The changeset's rules are the ones every password is held to; an unknown
  # key is reported alongside them.
  defp check_password(body, user, attrs) do
    changeset = User.password_changeset(user, attrs, hash_password: false)

    Errors.refuse(
      Request.unknown_keys(body, [], [:password]) ++
        Errors.from_changeset(changeset)
    )
  end
end
