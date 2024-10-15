defmodule Lightning.TokensTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Tokens

  setup do
    Mox.stub_with(Lightning.MockConfig, Lightning.Config.API)
    Mox.stub_with(LightningMock, Lightning.Stub)

    :ok
  end

  describe "verify with UserToken" do
    test "with a valid token" do
      user = insert(:user)

      Lightning.Stub.freeze_time(~U[2024-01-01 00:00:00Z])

      token = Lightning.Accounts.generate_api_token(user)

      assert {:ok, claims} = Tokens.verify(token)

      expected_sub = "user:#{user.id}"

      assert %{
               "iss" => "Lightning",
               "iat" => 1_704_067_200,
               "sub" => ^expected_sub,
               "jti" => _
             } = claims
    end

    test "with a forged/invalid token" do
      user = insert(:user)

      token = Lightning.Accounts.generate_api_token(user)

      replace_signer(:token_signer)

      assert {:error, :signature_error} = Tokens.verify(token)
    end
  end

  describe "verify with RunToken" do
    test "with a valid token" do
      Lightning.Stub.freeze_time(~U[2024-01-01 00:00:00Z])

      token =
        Lightning.Workers.generate_run_token(%{id: run_id = Ecto.UUID.generate()})

      assert {:ok, claims} = Tokens.verify(token)

      assert %{
               "exp" => 1_704_067_270,
               "id" => run_id,
               "iss" => "Lightning",
               "nbf" => 1_704_067_200,
               "sub" => "run:#{run_id}"
             } == claims
    end

    test "with a forged/invalid token" do
      token =
        Lightning.Workers.generate_run_token(%{id: Ecto.UUID.generate()})

      replace_signer(:run_token_signer)

      assert {:error, :signature_error} = Tokens.verify(token)
    end

    test "with an expired token" do
      Lightning.Stub.freeze_time(~U[2024-01-01 00:00:00Z])

      token =
        Lightning.Workers.generate_run_token(%{id: Ecto.UUID.generate()})

      Lightning.Stub.freeze_time(~U[2024-02-01 00:00:00Z])

      assert {
               :error,
               [message: "Invalid token", claim: "exp", claim_val: 1_704_067_270]
             } = Tokens.verify(token)
    end
  end

  # Generate a new RSA cert that is different to the one the token was
  # signed with.
  defp replace_signer(key) do
    Mox.stub(Lightning.MockConfig, key, fn ->
      {pvt, _pub} = Lightning.Utils.Crypto.generate_rsa_key_pair()
      Joken.Signer.create("RS256", %{"pem" => pvt})
    end)
  end
end
