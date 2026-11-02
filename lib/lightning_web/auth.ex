defmodule LightningWeb.Auth do
  @moduledoc """
  Request authentication for every HTTP route: what credentials the request
  sent, whether they match a trigger's or channel's webhook auth methods, and
  the refusal a failed login gets.

  Checking a bearer token is the core's job (`Lightning.Tokens`,
  `Lightning.ServiceAccount.AccessToken`, `Lightning.Accounts`); the plugs call
  this module to read the token and, when the check fails, to refuse.

  A refusal is a problem document with the `WWW-Authenticate` challenge the
  route's scheme calls for (RFC 6750 §3): a 401, or a 400 when the `Bearer`
  header can't be read. A refused permission is never a 401, so the one 403
  built here is `insufficient_scope`.

  All secret comparisons use `Plug.Crypto.secure_compare/2`.
  """
  import Plug.Conn, only: [get_req_header: 2]

  alias Lightning.Workflows.WebhookAuthMethod
  alias LightningWeb.API.Problem

  @type scheme :: :bearer | :session
  @type auth_methods :: [%{auth_type: :basic | :api}]

  @doc """
  The bearer token the request sent in its `Authorization` header.

  The scheme is matched without regard to case (RFC 9110 §11.1). A header with
  any other scheme, `Basic` included, is no token sent.
  A `Bearer` header with no token after it, or with whitespace inside the token,
  or more than one `Bearer` header, is a token sent but malformed.
  """
  @spec bearer_token(Plug.Conn.t()) ::
          {:ok, String.t()} | {:error, :missing | :malformed}
  def bearer_token(conn) do
    bearer_headers =
      for value <- get_req_header(conn, "authorization"),
          [scheme | token] <- [String.split(value)],
          String.downcase(scheme) == "bearer",
          do: token

    case bearer_headers do
      [] -> {:error, :missing}
      [[token]] -> {:ok, token}
      _malformed -> {:error, :malformed}
    end
  end

  @doc """
  Returns true if the request's `x-api-key` header matches any
  `:api`-type auth method in the list.
  """
  def valid_key?(conn, methods) do
    Enum.any?(methods, &key_matches?(conn, &1))
  end

  @doc """
  Returns true if the request's Basic Auth credentials match any
  `:basic`-type auth method in the list.
  """
  def valid_user?(conn, methods) do
    Enum.any?(methods, &user_matches?(conn, &1))
  end

  @doc """
  Returns true if the request contains an `x-api-key` or
  `authorization` header (regardless of whether the value is correct).
  """
  def has_credentials?(conn) do
    get_req_header(conn, "x-api-key") != [] or
      get_req_header(conn, "authorization") != []
  end

  @doc """
  Refuses a failed login, and halts: on a route that takes a bearer token or
  the session cookie, or on a trigger or channel, given its webhook auth
  methods.

  A bearer token refused for being `:expired` is told so in the challenge's
  `error_description`. Any other refusal says only what the request sent.

  A trigger or channel answers credentials sent but refused itself, so its
  refusal is always `unauthenticated`, never `invalid_token`.
  """
  @spec refuse(Plug.Conn.t(), scheme() | auth_methods(), :expired | nil) ::
          Plug.Conn.t()
  def refuse(conn, scheme_or_methods, reason \\ nil)

  def refuse(conn, :bearer, :expired) do
    respond(conn, :invalid_token, [
      bearer(
        ~s(error="invalid_token", error_description="The access token expired")
      )
    ])
  end

  def refuse(conn, :bearer, nil) do
    case bearer_token(conn) do
      {:error, :missing} ->
        respond(conn, :unauthenticated, [{"www-authenticate", "Bearer"}])

      {:error, :malformed} ->
        respond(conn, :invalid_request, [bearer(~s(error="invalid_request"))])

      {:ok, _token} ->
        respond(conn, :invalid_token, [bearer(~s(error="invalid_token"))])
    end
  end

  # No `Session` scheme is registered; browsers don't prompt for one they don't
  # know, which is the point (RFC 9110 §15.5.2 requires a challenge).
  def refuse(conn, :session, nil) do
    respond(conn, :unauthenticated, [
      {"www-authenticate", ~s(Session realm="Lightning")}
    ])
  end

  # A trigger or channel that its webhook auth methods didn't let in. It is
  # challenged for an API key when it takes one, and never for Basic: every
  # trigger lives under `/i/` and every channel under `/channels/`, so a browser
  # prompted for one Basic login may send it unasked to the others, where an
  # open trigger stores it in the dataclip and an open channel forwards it
  # upstream. A route that takes only Basic sends no challenge.
  def refuse(conn, auth_methods, nil) when is_list(auth_methods) do
    challenges =
      if Enum.any?(auth_methods, &(&1.auth_type == :api)),
        do: [{"www-authenticate", ~s(ApiKey header="x-api-key")}],
        else: []

    respond(conn, :unauthenticated, challenges)
  end

  @doc """
  The 403 for a token that lacks `grant`, naming it in both the body's `scope`
  and the challenge.
  """
  @spec insufficient_scope(String.t()) :: Problem.t()
  def insufficient_scope(grant) do
    Problem.new(:insufficient_scope,
      extensions: %{scope: grant},
      headers: [bearer(~s(error="insufficient_scope", scope="#{grant}"))]
    )
  end

  defp respond(conn, code, headers) do
    Problem.halt(conn, Problem.new(code, headers: headers))
  end

  defp bearer(params), do: {"www-authenticate", "Bearer " <> params}

  defp key_matches?(
         conn,
         %WebhookAuthMethod{
           auth_type: :api,
           api_key: key,
           scheduled_deletion: nil
         }
       ) do
    get_req_header(conn, "x-api-key")
    |> Enum.any?(fn header_value ->
      Plug.Crypto.secure_compare(header_value, key)
    end)
  end

  defp key_matches?(_, _), do: false

  defp user_matches?(conn, %WebhookAuthMethod{
         auth_type: :basic,
         username: expected_user,
         password: expected_pass,
         scheduled_deletion: nil
       }) do
    get_req_header(conn, "authorization")
    |> Enum.find_value(false, fn auth ->
      with [scheme, b64] <- String.split(auth, " ", parts: 2),
           true <- String.downcase(scheme) == "basic",
           {:ok, decoded} <- Base.decode64(b64),
           [user, pass] <- String.split(decoded, ":", parts: 2),
           true <- Plug.Crypto.secure_compare(user, expected_user),
           true <- Plug.Crypto.secure_compare(pass, expected_pass) do
        true
      else
        _ -> false
      end
    end)
  end

  defp user_matches?(_, _), do: false
end
