defmodule Lightning.ServiceAccount do
  @moduledoc """
  An identity that is not a person and proves who it is with an RSA key pair.

  Its `id` is the RFC 7638 thumbprint of its public key, so a new key is a new
  service account. Its `uuid`, for places that need one such as an audit
  event's actor, is a UUIDv5 of the thumbprint's RFC 9278 URI in the RFC 4122
  URL namespace, which any stock `uuid5` implementation reproduces.
  """

  @enforce_keys [:id, :uuid, :public_key]
  defstruct @enforce_keys

  @type t :: %__MODULE__{
          id: String.t(),
          uuid: Ecto.UUID.t(),
          public_key: JOSE.JWK.t()
        }

  @url_namespace <<0x6BA7B8119DAD11D180B400C04FD430C8::128>>

  @spec from_pem(String.t()) :: {:ok, t()} | {:error, String.t()}
  def from_pem(pem) do
    case JOSE.JWK.from_pem(pem) do
      %JOSE.JWK{kty: {:jose_jwk_kty_rsa, {:RSAPublicKey, _, _}}} = jwk ->
        id = JOSE.JWK.thumbprint(jwk)
        {:ok, %__MODULE__{id: id, uuid: uuid(id), public_key: jwk}}

      %JOSE.JWK{kty: {:jose_jwk_kty_rsa, _}} ->
        {:error, "holds a private key, not a public one"}

      _other ->
        {:error, "is not an RSA public key"}
    end
  rescue
    _ -> {:error, "is not an RSA public key"}
  end

  defp uuid(thumbprint) do
    <<a::48, _::4, b::12, _::2, c::62, _::32>> =
      :crypto.hash(
        :sha,
        @url_namespace <>
          "urn:ietf:params:oauth:jwk-thumbprint:sha-256:" <> thumbprint
      )

    Ecto.UUID.cast!(<<a::48, 5::4, b::12, 2::2, c::62>>)
  end
end
