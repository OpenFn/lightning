defmodule Lightning.ServiceAccountTest do
  use ExUnit.Case, async: true

  alias Lightning.ServiceAccount

  # The example key from RFC 7638 §3.1, whose thumbprint the RFC gives.
  @spki_pem """
  -----BEGIN PUBLIC KEY-----
  MIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA0vx7agoebGcQSuuPiLJX
  ZptN9nndrQmbXEps2aiAFbWhM78LhWx4cbbfAAtVT86zwu1RK7aPFFxuhDR1L6tS
  oc/BJECPebWKRXjBZCiFV4n3oknjhMstn64tZ/2W+5JsGY4Hc5n9yBXArwl93lqt
  7/RN5w6Cf0h4QyQ5v+65YGjQR0/FDW2QvzqY368QQMicAtaSqzs8KJZgnYb9c7d0
  zgdAZHzu6qMQvRL5hajrn1n91CbOpbISD08qNLyrdkt+bFTWhAI4vMQFh6WeZu0f
  M4lFd2NcRwr3XPksINHaQ+G/xBniIqbw0Ls1jF44+csFCur+kEgU8awapJzKnqDK
  gwIDAQAB
  -----END PUBLIC KEY-----
  """

  @pkcs1_pem """
  -----BEGIN RSA PUBLIC KEY-----
  MIIBCgKCAQEA0vx7agoebGcQSuuPiLJXZptN9nndrQmbXEps2aiAFbWhM78LhWx4
  cbbfAAtVT86zwu1RK7aPFFxuhDR1L6tSoc/BJECPebWKRXjBZCiFV4n3oknjhMst
  n64tZ/2W+5JsGY4Hc5n9yBXArwl93lqt7/RN5w6Cf0h4QyQ5v+65YGjQR0/FDW2Q
  vzqY368QQMicAtaSqzs8KJZgnYb9c7d0zgdAZHzu6qMQvRL5hajrn1n91CbOpbIS
  D08qNLyrdkt+bFTWhAI4vMQFh6WeZu0fM4lFd2NcRwr3XPksINHaQ+G/xBniIqbw
  0Ls1jF44+csFCur+kEgU8awapJzKnqDKgwIDAQAB
  -----END RSA PUBLIC KEY-----
  """

  @thumbprint "NzbLsXh8uDCcd-6MNwXF4W_7noWXFZAfHkxZsRGC9Xs"

  # Python: uuid.uuid5(uuid.NAMESPACE_URL,
  #   "urn:ietf:params:oauth:jwk-thumbprint:sha-256:" + thumbprint)
  @uuid "e759693d-df5d-5f5a-b4ae-a182d4fd378e"

  describe "from_pem/1" do
    test "identifies the service account by its key's RFC 7638 thumbprint" do
      assert {:ok, %ServiceAccount{id: @thumbprint, uuid: @uuid}} =
               ServiceAccount.from_pem(@spki_pem)

      assert {:ok, %ServiceAccount{id: @thumbprint, uuid: @uuid}} =
               ServiceAccount.from_pem(@pkcs1_pem)
    end

    test "gives a new key a new id and uuid" do
      {_, pem} =
        JOSE.JWK.generate_key({:rsa, 2048})
        |> JOSE.JWK.to_public()
        |> JOSE.JWK.to_pem()

      assert {:ok, account} = ServiceAccount.from_pem(pem)
      refute account.id == @thumbprint
      refute account.uuid == @uuid
      assert {:ok, ^account} = ServiceAccount.from_pem(pem)
    end

    test "refuses a private key" do
      {_, pem} = JOSE.JWK.generate_key({:rsa, 2048}) |> JOSE.JWK.to_pem()

      assert {:error, "holds a private key, not a public one"} =
               ServiceAccount.from_pem(pem)
    end

    test "refuses a key that is not RSA" do
      pem = """
      -----BEGIN PUBLIC KEY-----
      MFkwEwYHKoZIzj0CAQYIKoZIzj0DAQcDQgAE7aBIw3Zoq85rGk4EC+MBrElUg/Ym
      rmZUyENZbakktntXDTlHKCREjMuHitBVcQg2xZJL+9zNCbL2Uaj3AkzIxQ==
      -----END PUBLIC KEY-----
      """

      assert {:error, "is not an RSA public key"} = ServiceAccount.from_pem(pem)
    end

    test "refuses text that is not a PEM" do
      assert {:error, "is not an RSA public key"} =
               ServiceAccount.from_pem("not a key")

      truncated = """
      -----BEGIN PUBLIC KEY-----
      MFkwEwYHKoZIzj0CAQYIKoZIzj0D
      -----END PUBLIC KEY-----
      """

      assert {:error, "is not an RSA public key"} =
               ServiceAccount.from_pem(truncated)
    end
  end
end
