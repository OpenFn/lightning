defmodule Lightning.AuthProviders.Handler do
  @moduledoc """
  Module which wraps Oauth configuration and a WellKnown document
  into a convenient struct that can be used to authenticate users against
  any OIDC compliant provider.
  """

  alias Lightning.AuthProviders.TLS
  alias Lightning.AuthProviders.WellKnown

  @jwks_cache :auth_provider_jwks
  @jwks_ttl :timer.minutes(10)

  # Asymmetric algorithms only. Restricting the accepted set (never `none`, never
  # an HMAC alg) is what stops an "alg confusion" forgery where a token signed
  # with a symmetric alg is verified against the provider's public key.
  @id_token_algs ~w(RS256 RS384 RS512 ES256 ES384 ES512)

  @type t :: %__MODULE__{
          name: String.t(),
          client: OAuth2.Client.t(),
          wellknown: WellKnown.t(),
          scope: String.t(),
          allow_unverified_email: boolean()
        }

  @type opts :: [
          client_id: String.t(),
          client_secret: String.t(),
          redirect_uri: String.t(),
          wellknown: WellKnown.t(),
          scope: String.t(),
          allow_unverified_email: boolean()
        ]

  defstruct [
    :name,
    :client,
    :wellknown,
    scope: "openid email profile",
    allow_unverified_email: false
  ]

  @doc """
  Create a new Provider struct, expects a name and opts:

  - `:client_id` - The providers issued id
  - `:client_secret` - Secret for the client
  - `:redirect_uri` - The URI for redirecting after authentication,
    usually the callback url in the router.
  - `:wellknown` - A AuthProviders.WellKnown struct with the providers
    `.well-known/openid-configuration`.
  """
  @spec new(name :: String.t(), opts :: opts()) ::
          {:ok, __MODULE__.t()} | {:error, term()}
  def new(name, opts) do
    case validate_opts(opts) do
      {:error, error} ->
        {:error, error}

      :ok ->
        wellknown = opts[:wellknown]
        scope = opts[:scope] || "openid email profile"

        client =
          OAuth2.Client.new(
            strategy: OAuth2.Strategy.AuthCode,
            client_id: opts[:client_id],
            client_secret: opts[:client_secret],
            authorize_url: wellknown.authorization_endpoint,
            token_url: wellknown.token_endpoint,
            redirect_uri: opts[:redirect_uri],
            # Verify the TLS chain on the token exchange: that POST carries the
            # client_secret and the auth code, so a MITM here would capture the
            # RP's long-lived secret. (The scheme is enforced in get_token/2,
            # since these opts are inert over plaintext http.) OAuth2 runs on the
            # Tesla/Hackney adapter, which reads `ssl_options` (not `ssl`), so we
            # verify against the same OS trust store the HTTPoison fetches use.
            request_opts: [ssl_options: TLS.verify_opts()]
          )
          |> OAuth2.Client.put_serializer("application/json", Jason)

        {:ok,
         struct!(__MODULE__,
           name: name,
           client: client,
           wellknown: wellknown,
           scope: scope,
           allow_unverified_email: opts[:allow_unverified_email] || false
         )}
    end
  end

  @doc """
  Returns a Handler from a given AuthConfig
  """
  @spec from_model(model :: nil | Lightning.AuthProviders.AuthConfig.t()) ::
          {:ok, __MODULE__.t()} | {:error, term()}

  def from_model(nil), do: {:error, :not_found}

  def from_model(model) do
    # Handle a failed discovery fetch (e.g. TLS verification against an internal
    # IdP's untrusted CA) as an error rather than threading the error tuple into
    # `new/2`, which would crash on `Map.from_struct`.
    case WellKnown.fetch(model.discovery_url) do
      {:ok, wellknown} ->
        opts =
          model
          |> Map.from_struct()
          |> Keyword.new(fn
            {:discovery_url, _v} -> {:wellknown, wellknown}
            {k, v} -> {k, v}
          end)

        new(model.name, opts)

      {:error, reason} ->
        {:error, reason}
    end
  end

  @doc """
  Builds the provider authorize URL.

  Extra `params` (e.g. `state:`) are forwarded to the OAuth2 client; the
  configured `scope` is always included. Callers should pass an unguessable
  `state` to protect the callback against CSRF.
  """
  @spec authorize_url(handler :: __MODULE__.t(), params :: keyword()) ::
          String.t()
  def authorize_url(handler, params \\ []) do
    OAuth2.Client.authorize_url!(
      handler.client,
      Keyword.put(params, :scope, handler.scope)
    )
  end

  @spec get_token(handler :: __MODULE__.t(), code :: String.t()) ::
          {:ok, OAuth2.AccessToken.t()} | {:error, map() | atom()}
  def get_token(handler, code) when is_binary(code) do
    case OAuth2.Client.get_token(handler.client,
           code: code,
           scope: handler.scope
         ) do
      {:ok, client} -> {:ok, client.token}
      {:error, %OAuth2.Response{body: body}} -> {:error, body}
      {:error, %OAuth2.Error{}} -> {:error, :token_request_failed}
    end
  end

  @spec get_userinfo(handler :: __MODULE__.t(), token :: OAuth2.AccessToken.t()) ::
          {:ok, map()} | {:error, term()}
  def get_userinfo(handler, token) do
    client = %{handler.client | token: token}

    case OAuth2.Client.get(client, handler.wellknown.userinfo_endpoint) do
      {:ok, %OAuth2.Response{body: userinfo}} ->
        {:ok, maybe_resolve_email(client, handler.wellknown, userinfo)}

      {:error, reason} ->
        {:error, reason}
    end
  end

  # Some providers (e.g. GitHub) don't carry a verification status in userinfo.
  # The `/user/emails` endpoint is authoritative, so we derive `email_verified`
  # from it rather than assuming a present userinfo email is verified.
  defp maybe_resolve_email(
         client,
         %{user_emails_endpoint: endpoint},
         %{} = userinfo
       )
       when is_binary(endpoint) do
    emails = fetch_emails(client, endpoint)

    if is_binary(userinfo["email"]) do
      Map.put(userinfo, "email_verified", verified?(emails, userinfo["email"]))
    else
      case select_primary_verified_email(emails) do
        nil ->
          userinfo

        email ->
          userinfo
          |> Map.put("email", email)
          |> Map.put("email_verified", true)
      end
    end
  end

  defp maybe_resolve_email(_client, _wellknown, userinfo), do: userinfo

  defp fetch_emails(client, endpoint) do
    case OAuth2.Client.get(client, endpoint) do
      {:ok, %OAuth2.Response{body: emails}} when is_list(emails) -> emails
      _ -> []
    end
  end

  defp verified?(emails, email) do
    target = String.downcase(email)

    Enum.any?(emails, fn
      %{"verified" => true, "email" => candidate} when is_binary(candidate) ->
        String.downcase(candidate) == target

      _ ->
        false
    end)
  end

  defp select_primary_verified_email(emails) do
    primary =
      Enum.find_value(emails, fn
        %{"primary" => true, "verified" => true, "email" => email} -> email
        _ -> nil
      end)

    primary ||
      Enum.find_value(emails, fn
        %{"verified" => true, "email" => email} -> email
        _ -> nil
      end)
  end

  @doc """
  Verifies the `id_token` returned by the token endpoint and returns its claims.

  Checks the JWT signature against the provider's JWKS (asymmetric algs only),
  then that `iss` matches the discovered issuer, `aud` contains our client id,
  the token is not expired, and `nonce` matches the value we sent. This is what
  lets the caller trust the token's identity claims (`email`, `email_verified`,
  `sub`) rather than an unauthenticated userinfo response.
  """
  @spec verify_id_token(
          handler :: __MODULE__.t(),
          token :: OAuth2.AccessToken.t(),
          nonce :: String.t() | nil
        ) :: {:ok, map()} | {:error, term()}
  def verify_id_token(handler, token, nonce) do
    with {:ok, id_token} <- fetch_id_token(token),
         {:ok, claims} <- verify_signature(handler, id_token) do
      verify_claims(handler, claims, nonce)
    end
  end

  defp fetch_id_token(%OAuth2.AccessToken{
         other_params: %{"id_token" => id_token}
       })
       when is_binary(id_token),
       do: {:ok, id_token}

  defp fetch_id_token(_token), do: {:error, :missing_id_token}

  defp verify_signature(handler, id_token) do
    with {:ok, header} <- peek_header(id_token),
         {:ok, keys} <- signing_keys(handler.wellknown.jwks_uri, header) do
      keys
      |> candidate_keys(header)
      |> verify_with_keys(id_token)
    end
  rescue
    _ -> {:error, :invalid_id_token}
  end

  # Serve the provider's signing keys from cache to keep the JWKS fetch off the
  # per-login hot path.
  defp signing_keys(jwks_uri, header) do
    case Cachex.get(@jwks_cache, jwks_uri) do
      # Cold cache: fetch fresh. The result is already current, so there's no
      # point refetching even if this token's kid isn't in it.
      {:ok, nil} ->
        refresh_jwks(jwks_uri)

      # Warm cache: reuse it, unless the token names a `kid` the cached set
      # doesn't hold, in which case a key may have just rotated in, so fetch
      # fresh once. A steady miss is no worse than the uncached per-login fetch.
      {:ok, keys} ->
        if kid_present?(keys, header),
          do: {:ok, keys},
          else: refresh_jwks(jwks_uri)

      # Cache unavailable: fall back to a direct fetch.
      _ ->
        fetch_jwks(jwks_uri)
    end
  end

  defp refresh_jwks(jwks_uri) do
    with {:ok, keys} <- fetch_jwks(jwks_uri) do
      Cachex.put(@jwks_cache, jwks_uri, keys, ttl: @jwks_ttl)
      {:ok, keys}
    end
  end

  defp kid_present?(keys, %{"kid" => kid}) when is_binary(kid),
    do: Enum.any?(keys, &(&1["kid"] == kid))

  defp kid_present?(_keys, _header), do: true

  defp peek_header(id_token) do
    {:ok, id_token |> JOSE.JWS.peek_protected() |> Jason.decode!()}
  rescue
    _ -> {:error, :malformed_id_token}
  end

  # With a `kid`, only that key can be the signer. Without one, any of the
  # provider's signing keys might be, so try them all (a JWKS can lead with an
  # encryption key or, mid-rotation, the previous key).
  defp candidate_keys(keys, %{"kid" => kid}) when is_binary(kid),
    do: Enum.filter(keys, &(&1["kid"] == kid))

  defp candidate_keys(keys, _header),
    do: Enum.filter(keys, &(&1["use"] in [nil, "sig"]))

  defp verify_with_keys([], _id_token), do: {:error, :invalid_signature}

  defp verify_with_keys([key | rest], id_token) do
    case verify_one_key(key, id_token) do
      {:ok, claims} -> {:ok, claims}
      :error -> verify_with_keys(rest, id_token)
    end
  end

  # A malformed/unsupported key entry must only skip that key, not abort the
  # whole verification, so a valid signing key later in the set is still tried.
  defp verify_one_key(key, id_token) do
    jwk = JOSE.JWK.from_map(key)

    case JOSE.JWT.verify_strict(jwk, @id_token_algs, id_token) do
      {true, %JOSE.JWT{fields: claims}, _jws} -> {:ok, claims}
      _ -> :error
    end
  rescue
    _ -> :error
  end

  defp fetch_jwks(nil), do: {:error, :missing_jwks_uri}

  defp fetch_jwks(jwks_uri) do
    if TLS.secure_url?(jwks_uri),
      do: get_jwks(jwks_uri),
      else: {:error, :insecure_jwks_uri}
  end

  defp get_jwks(jwks_uri) do
    opts = [ssl: TLS.verify_opts(), timeout: 10_000, recv_timeout: 10_000]

    case HTTPoison.get(jwks_uri, [], opts) do
      {:ok, %HTTPoison.Response{status_code: 200, body: body}} ->
        case Jason.decode(body) do
          {:ok, %{"keys" => keys}} when is_list(keys) -> {:ok, keys}
          _ -> {:error, :invalid_jwks}
        end

      _ ->
        {:error, :jwks_fetch_failed}
    end
  end

  defp verify_claims(handler, claims, nonce) do
    cond do
      is_nil(handler.wellknown.issuer) ->
        {:error, :missing_issuer}

      claims["iss"] != handler.wellknown.issuer ->
        {:error, :invalid_issuer}

      not audience_valid?(claims, handler.client.client_id) ->
        {:error, :invalid_audience}

      expired?(claims["exp"]) ->
        {:error, :expired}

      is_nil(nonce) ->
        {:error, :missing_nonce}

      claims["nonce"] != nonce ->
        {:error, :invalid_nonce}

      true ->
        {:ok, claims}
    end
  end

  # `aud` must contain our client id. When it lists more than one audience the
  # OIDC spec requires `azp` to name us; and if `azp` is present at all it must
  # be us, so a token minted for another client at the same issuer is rejected.
  defp audience_valid?(claims, client_id) do
    aud = List.wrap(claims["aud"])
    azp = claims["azp"]

    cond do
      client_id not in aud -> false
      length(aud) > 1 -> azp == client_id
      not is_nil(azp) -> azp == client_id
      true -> true
    end
  end

  defp expired?(exp) when is_integer(exp), do: exp <= System.system_time(:second)
  defp expired?(_exp), do: true

  defp validate_opts(opts) do
    with nil <-
           [:client_id, :client_secret, :redirect_uri, :wellknown]
           |> expect_key(opts, fn key ->
             "Provider expects a '#{key}' key."
           end),
         nil <-
           [:authorization_endpoint, :token_endpoint]
           |> expect_key(opts[:wellknown] |> Map.from_struct(), fn key ->
             "Provider expects a WellKnown struct with a '#{key}' key."
           end) do
      :ok
    else
      e -> e
    end
  end

  defp expect_key(keys, opts, err_func) do
    keys
    |> Enum.map(fn key ->
      if get_in(opts, [key]), do: :ok, else: {:error, err_func.(key)}
    end)
    |> Enum.find(&match?({:error, _}, &1))
  end
end
