defmodule Lightning.ServiceAccountHelpers do
  @moduledoc false

  alias Lightning.ServiceAccount
  alias Lightning.ServiceAccount.AccessToken

  @doc """
  A fresh key pair and the service account its public half registers.
  """
  def service_account_with_key do
    private_key = JOSE.JWK.generate_key({:rsa, 2048})
    {_, pem} = private_key |> JOSE.JWK.to_public() |> JOSE.JWK.to_pem()
    {:ok, account} = ServiceAccount.from_pem(pem)
    {account, private_key}
  end

  @doc """
  The claims of an assertion jig would send, overridden by `overrides`.
  """
  def assertion_claims(%ServiceAccount{id: id}, audience, overrides \\ %{}) do
    now = System.system_time(:second)

    Map.merge(
      %{
        "iss" => id,
        "sub" => id,
        "aud" => audience,
        "iat" => now,
        "exp" => now + 60,
        "jti" => Ecto.UUID.generate()
      },
      overrides
    )
  end

  def sign_assertion(private_key, claims, header \\ %{"alg" => "RS256"}) do
    {_, token} =
      private_key |> JOSE.JWT.sign(header, claims) |> JOSE.JWS.compact()

    token
  end

  @doc """
  An access token for `account` carrying `scope`, signed as Lightning signs
  one, that expired a second ago.
  """
  def expired_access_token(%ServiceAccount{id: id}, scope) do
    sign_assertion(
      Lightning.Config.token_signer().jwk,
      %{
        "iss" => AccessToken.issuer(),
        "aud" => AccessToken.issuer() <> "/api",
        "sub" => id,
        "scope" => scope,
        "exp" => System.system_time(:second) - 1
      },
      %{"alg" => "RS256", "typ" => "at+jwt"}
    )
  end

  @doc """
  A token that claims `alg: none` and carries no signature.
  """
  def unsigned_assertion(claims) do
    encode = &Base.url_encode64(Jason.encode!(&1), padding: false)
    encode.(%{"alg" => "none"}) <> "." <> encode.(claims) <> "."
  end
end
