defmodule Lightning.AuthProviders.ClientAssertion do
  @moduledoc """
  Generates signed JWT client assertions for `private_key_jwt`
  OAuth client authentication per RFC 7523.
  """
  use Joken.Config

  @impl true
  def token_config do
    %{}
    |> add_claim("iat", fn -> DateTime.utc_now() |> DateTime.to_unix() end)
    |> add_claim("exp", fn ->
      DateTime.utc_now() |> DateTime.add(300, :second) |> DateTime.to_unix()
    end)
    |> add_claim("jti", fn -> Ecto.UUID.generate() end)
  end

  @spec build(client :: map()) :: {:ok, String.t()} | {:error, term()}
  def build(client) do
    signer = Joken.Signer.create("RS256", %{"pem" => client.private_key})

    claims = %{
      "iss" => client.client_id,
      "sub" => client.client_id,
      "aud" => client.token_endpoint
    }

    case generate_and_sign(claims, signer) do
      {:ok, token, _claims} -> {:ok, token}
      {:error, reason} -> {:error, reason}
    end
  rescue
    e in ArgumentError -> {:error, e}
  end
end
