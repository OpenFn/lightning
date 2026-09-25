defmodule Lightning.ServiceAccountHelpers do
  @moduledoc false

  alias Lightning.ServiceAccount

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
  A token that claims `alg: none` and carries no signature.
  """
  def unsigned_assertion(claims) do
    encode = &Base.url_encode64(Jason.encode!(&1), padding: false)
    encode.(%{"alg" => "none"}) <> "." <> encode.(claims) <> "."
  end
end
