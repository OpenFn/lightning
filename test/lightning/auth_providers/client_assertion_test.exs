defmodule Lightning.AuthProviders.ClientAssertionTest do
  use ExUnit.Case, async: true

  alias Lightning.AuthProviders.ClientAssertion

  @test_pem (
              rsa_key = :public_key.generate_key({:rsa, 2048, 65537})
              pem_entry = :public_key.pem_entry_encode(:RSAPrivateKey, rsa_key)
              :public_key.pem_encode([pem_entry])
            )

  @test_client %{
    client_id: "test-client-id",
    private_key: @test_pem,
    token_endpoint: "https://example.com/token"
  }

  describe "build/1" do
    test "generates a valid JWT with correct header and claims" do
      assert {:ok, token} = ClientAssertion.build(@test_client)
      assert is_binary(token)

      # Verify header
      protected = JOSE.JWT.peek_protected(token)
      assert %JOSE.JWS{alg: {:jose_jws_alg_rsa_pkcs1_v1_5, :RS256}} = protected

      # Verify claims
      payload = JOSE.JWT.peek_payload(token)

      assert %JOSE.JWT{
               fields: %{
                 "iss" => "test-client-id",
                 "sub" => "test-client-id",
                 "aud" => "https://example.com/token",
                 "exp" => exp,
                 "iat" => iat,
                 "jti" => jti
               }
             } = payload

      # exp is approximately 5 minutes (300 seconds) after iat
      assert exp - iat == 300

      # jti is a valid UUID
      assert {:ok, _} = Ecto.UUID.cast(jti)
    end

    test "generates unique jti values across multiple calls" do
      {:ok, token_1} = ClientAssertion.build(@test_client)
      {:ok, token_2} = ClientAssertion.build(@test_client)

      %JOSE.JWT{fields: %{"jti" => jti_1}} = JOSE.JWT.peek_payload(token_1)
      %JOSE.JWT{fields: %{"jti" => jti_2}} = JOSE.JWT.peek_payload(token_2)

      refute jti_1 == jti_2
    end

    test "returns error for an invalid PEM key" do
      client = %{@test_client | private_key: "not-a-valid-pem-key"}

      assert {:error, _reason} = ClientAssertion.build(client)
    end
  end
end
