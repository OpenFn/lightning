defmodule Lightning.AuthProviders.TLS do
  @moduledoc """
  Shared TLS settings for the OIDC login fetches (discovery, JWKS, userinfo).

  These endpoints supply or carry the material used to authenticate an SSO
  login, so they must be fetched over verified HTTPS: a MITM on any of them
  would let an attacker substitute keys/claims and forge a login.
  """

  @doc "HTTPoison `:ssl` options that verify the server's certificate chain."
  def verify_opts do
    [
      verify: :verify_peer,
      cacerts: :public_key.cacerts_get(),
      customize_hostname_check: [
        match_fun: :public_key.pkix_verify_hostname_match_fun(:https)
      ]
    ]
  end

  @doc """
  True when the URL is https, so `verify_opts/0` actually applies.

  Plaintext http over a loopback host is accepted only when
  `:auth_providers_allow_insecure_loopback` is set (the test suite serves these
  endpoints over http on localhost); in production it is refused, so a
  misconfigured plaintext endpoint can't silently skip chain verification.
  """
  def secure_url?(url) when is_binary(url) do
    case URI.parse(url) do
      %URI{scheme: "https"} ->
        true

      %URI{host: host} ->
        allow_insecure_loopback?() and host in ["localhost", "127.0.0.1", "::1"]
    end
  end

  # A missing/blank endpoint (e.g. an empty form field, or a discovery doc that
  # omits one) is treated as insecure so callers fail closed rather than crash.
  def secure_url?(_url), do: false

  defp allow_insecure_loopback? do
    Application.get_env(
      :lightning,
      :auth_providers_allow_insecure_loopback,
      false
    )
  end
end
