defmodule Lightning.ServiceAccount.AccessToken do
  @moduledoc """
  The RFC 9068 access token a service account gets from the token endpoint.

  It lasts five minutes and nothing about it is stored. Its `typ` of `at+jwt`
  and its own `aud` are what tell it apart from personal access tokens and run
  tokens, which are signed with the same key.
  """

  alias Lightning.ServiceAccount

  @scopes [
    "users:read",
    "users:write",
    "projects:write",
    "credentials:write",
    "collections:write"
  ]
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
  Whether `token` declares itself an access token by its `typ`, without
  checking anything else about it.
  """
  @spec access_token?(String.t()) :: boolean()
  def access_token?(token) do
    match?(%{"typ" => @typ}, Jason.decode!(JOSE.JWS.peek_protected(token)))
  rescue
    _ -> false
  end

  @doc """
  Returns the service account `token` was issued to, holding the token's scopes
  as its `grants`.

  A token is only good for the service account registered now, so registering
  a new key, or unsetting it, cuts off tokens already issued.
  `{:error, :expired}` is only for a token that would otherwise be good and
  whose `exp` has passed. Anything else wrong is `{:error, :invalid}`.
  """
  @spec verify(String.t()) ::
          {:ok, ServiceAccount.t()} | {:error, :expired | :invalid}
  def verify(token) do
    jwk = Lightning.Config.token_signer().jwk
    issuer = issuer()
    audience = audience()

    with %ServiceAccount{id: id} = service_account <-
           Lightning.Config.service_account(),
         {true,
          %JOSE.JWT{
            fields:
              %{"iss" => ^issuer, "aud" => ^audience, "sub" => ^id, "exp" => exp} =
                claims
          }, %JOSE.JWS{fields: %{"typ" => @typ}}}
         when is_integer(exp) <- JOSE.JWT.verify_strict(jwk, ["RS256"], token) do
      if exp > System.system_time(:second),
        do: {:ok, %{service_account | grants: grants(claims)}},
        else: {:error, :expired}
    else
      _other -> {:error, :invalid}
    end
  rescue
    _ -> {:error, :invalid}
  end

  defp grants(claims),
    do: claims |> Map.get("scope", "") |> String.split() |> MapSet.new()
end
