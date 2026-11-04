defmodule LightningWeb.TokenEndpointError do
  @moduledoc """
  What the OAuth token endpoint answers when it refuses a token request: for
  each reason, the status, the OAuth `error` code and an `error_description`
  saying why.

  Bodies are OAuth error responses (RFC 6749 §5.2), never problem documents.
  Each description is fixed per reason and repeats nothing from the request.
  It stays inside the characters §5.2 allows, which leave out `"` and `\\`.
  """

  import Phoenix.Controller, only: [json: 2]
  import Plug.Conn, only: [put_status: 2]

  alias Lightning.ServiceAccount.Assertion

  @type reason ::
          Assertion.error()
          | :not_form_encoded
          | :no_grant_type
          | :unsupported_grant_type
          | :no_client_assertion
          | :scope_not_a_string
          | :no_scope
          | :unknown_scope
          | :unreadable_request
          | :request_too_large

  @refusals %{
    unreadable_request:
      {400, "invalid_request",
       "The request could not be parsed. Send the parameters form-encoded, " <>
         "as application/x-www-form-urlencoded, in the body."},
    request_too_large:
      {413, "invalid_request", "The body is larger than this server accepts."},
    not_form_encoded:
      {400, "invalid_request",
       "The body must be form-encoded, as application/x-www-form-urlencoded."},
    no_grant_type:
      {400, "invalid_request",
       "The body has no single grant_type value. Send " <>
         "grant_type=client_credentials in the form-encoded body, not the " <>
         "query string."},
    unsupported_grant_type:
      {400, "unsupported_grant_type", "grant_type must be client_credentials."},
    no_client_assertion:
      {400, "invalid_request",
       "Send client_assertion_type " <>
         "urn:ietf:params:oauth:client-assertion-type:jwt-bearer and the " <>
         "signed JWT in client_assertion."},
    scope_not_a_string:
      {400, "invalid_request",
       "scope must be one value, with token grants separated by spaces."},
    no_scope:
      {400, "invalid_scope",
       "scope is missing or empty. Name the token grants you need, " <>
         "separated by spaces."},
    unknown_scope:
      {400, "invalid_scope",
       "scope names something that is not a token grant. scopes_supported " <>
         "in /.well-known/oauth-authorization-server lists them."},
    malformed:
      {401, "invalid_client", "client_assertion is not a JWT with an iss claim."},
    unknown_service_account:
      {401, "invalid_client",
       "The assertion's iss is not this server's service account id."},
    bad_signature:
      {401, "invalid_client",
       "The assertion's signature does not verify with the service " <>
         "account's public key. Sign it with RS256 and the matching " <>
         "private key."},
    wrong_subject:
      {401, "invalid_client",
       "The assertion's sub must be the service account id, the same as " <>
         "its iss."},
    wrong_audience:
      {401, "invalid_client",
       "The assertion's aud must be exactly the token_endpoint URL in " <>
         "/.well-known/oauth-authorization-server."},
    missing_claims:
      {401, "invalid_client",
       "The assertion needs integer exp and iat claims, and a jti of 1 to " <>
         "255 bytes with no NUL character."},
    expired:
      {401, "invalid_client",
       "The assertion's exp has passed. Check the client's clock."},
    lives_too_long:
      {401, "invalid_client",
       "The assertion's exp is more than 60 seconds after its iat."},
    issued_in_future:
      {401, "invalid_client",
       "The assertion's iat is more than 5 seconds ahead of the server's " <>
         "clock. Check the client's clock."},
    wrong_client_id:
      {401, "invalid_client",
       "client_id must be the service account id, the same as the " <>
         "assertion's iss, or be left out."},
    replayed:
      {401, "invalid_client",
       "This assertion's jti has been used before. Sign a new assertion " <>
         "with a new jti for each token request."}
  }

  @raise_reasons %{
    Plug.Conn.InvalidQueryError => :unreadable_request,
    Plug.Parsers.BadEncodingError => :unreadable_request,
    Plug.Parsers.ParseError => :unreadable_request,
    Plug.Parsers.RequestTooLargeError => :request_too_large
  }

  @doc "Every reason the token endpoint refuses a request for."
  @spec reasons() :: [reason()]
  def reasons, do: Map.keys(@refusals)

  @doc """
  Answers `conn` with the refusal for `reason`.

  The 401s carry no `WWW-Authenticate`: the client authenticates in the body,
  and no HTTP authentication scheme describes that.
  """
  @spec respond(Plug.Conn.t(), reason()) :: Plug.Conn.t()
  def respond(conn, reason) do
    {status, error, description} = Map.fetch!(@refusals, reason)

    conn
    |> put_status(status)
    |> json(%{error: error, error_description: description})
  end

  @doc """
  Whether the token endpoint answers `exception` itself. It answers a request
  it could not read, which the client caused, and nothing else.
  """
  @spec answers_raise?(term()) :: boolean()
  def answers_raise?(exception),
    do: is_struct(exception) and is_map_key(@raise_reasons, exception.__struct__)

  @doc """
  Answers `conn` with the refusal for `exception`, which must be one
  `answers_raise?/1` accepts.
  """
  @spec respond_to_raise(Plug.Conn.t(), Exception.t()) :: Plug.Conn.t()
  def respond_to_raise(conn, %exception{}),
    do: respond(conn, Map.fetch!(@raise_reasons, exception))
end
