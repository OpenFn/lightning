defmodule Lightning.Utils.Crypto do
  @moduledoc """
  Utility functions for cryptographic operations.
  """

  @doc """
  Generates a new RSA key pair with 2048 bits and a public exponent of 65537.

  This is preferable to using `create_private_key` and `abstract_public_key` as
  it generates a key pair in one step, and also doesn't require shelling out to
  `openssl`.
  """
  def generate_rsa_key_pair do
    {:RSAPrivateKey, _, modulus, public_exponent, _, _, _, _exponent1, _, _,
     _other_prime_infos} =
      rsa_private_key = :public_key.generate_key({:rsa, 2048, 65_537})

    rsa_public_key = {:RSAPublicKey, modulus, public_exponent}

    private_key =
      [:public_key.pem_entry_encode(:RSAPrivateKey, rsa_private_key)]
      |> :public_key.pem_encode()

    public_key =
      [:public_key.pem_entry_encode(:RSAPublicKey, rsa_public_key)]
      |> :public_key.pem_encode()

    {private_key, public_key}
  end

  @doc """
  Generates a new HS256 key.
  """
  def generate_hs256_key do
    32 |> :crypto.strong_rand_bytes() |> Base.encode64()
  end
end
