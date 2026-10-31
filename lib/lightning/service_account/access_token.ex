defmodule Lightning.ServiceAccount.AccessToken do
  @moduledoc """
  The RFC 9068 access token a service account gets from the token endpoint.

  It lasts five minutes and nothing about it is stored. Its `typ` of `at+jwt`
  and its own `aud` are what tell it apart from personal access tokens and run
  tokens, which are signed with the same key.
  """

  alias Lightning.ServiceAccount

  @scopes ["users:read", "users:write"]
  @lifetime 300
  @typ "at+jwt"

  @spec scopes() :: [String.t()]
  def scopes, do: @scopes

  @spec lifetime() :: pos_integer()
  def lifetime, do: @lifetime

  @spec issuer() :: String.t()
  def issuer, do: LightningWeb.Endpoint.url()

  defp audience, do: issuer() <> "/api"

  @spec issue(ServiceAccount.t(), [String.t()]) :: String.t()
  def issue(%ServiceAccount{id: id}, scopes) do
    now = System.system_time(:second)

    claims = %{
      "iss" => issuer(),
      "aud" => audience(),
      "sub" => id,
      "client_id" => id,
      "scope" => Enum.join(scopes, " "),
      "iat" => now,
      "exp" => now + @lifetime,
      "jti" => Ecto.UUID.generate()
    }

    {_, token} =
      Lightning.Config.token_signer().jwk
      |> JOSE.JWT.sign(%{"alg" => "RS256", "typ" => @typ}, claims)
      |> JOSE.JWS.compact()

    token
  end

  @doc """
  Returns the claims of `token` when its `typ`, signature, `iss`, `aud` and
  `exp` all check out.
  """
  @spec verify(String.t()) :: {:ok, map()} | {:error, :invalid}
  def verify(token) do
    jwk = Lightning.Config.token_signer().jwk
    issuer = issuer()
    audience = audience()
    now = System.system_time(:second)

    case JOSE.JWT.verify_strict(jwk, ["RS256"], token) do
      {true,
       %JOSE.JWT{
         fields: %{"iss" => ^issuer, "aud" => ^audience, "exp" => exp} = claims
       }, %JOSE.JWS{fields: %{"typ" => @typ}}}
      when is_integer(exp) and exp > now ->
        {:ok, claims}

      _other ->
        {:error, :invalid}
    end
  rescue
    _ -> {:error, :invalid}
  end
end
