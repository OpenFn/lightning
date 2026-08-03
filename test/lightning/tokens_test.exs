defmodule Lightning.TokensTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  alias Lightning.Tokens

  setup do
    Mox.stub_with(Lightning.MockConfig, Lightning.Config.API)
    Mox.stub_with(LightningMock, Lightning.Stub)

    :ok
  end

  describe "UserToken" do
    test "verify a valid token" do
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

    test "verify a forged/invalid token" do
      user = insert(:user)

      token = Lightning.Accounts.generate_api_token(user)

      replace_signer(:token_signer)

      assert {:error, :signature_error} = Tokens.verify(token)
    end

    test "retrieving the subject from the token" do
      Lightning.Stub.freeze_time(DateTime.utc_now())
      user = insert(:user)

      token = Lightning.Accounts.generate_api_token(user)

      assert {:ok, claims} = Tokens.verify(token)

      assert Tokens.get_subject(claims) == user |> Repo.reload!()
    end

    test "rejects a disabled user's token at the verification boundary" do
      user = insert(:user, disabled: true)
      token = Lightning.Accounts.generate_api_token(user)

      assert {:error, :user_blocked} = Tokens.verify(token)
    end

    test "rejects a token for a user scheduled for deletion" do
      user = insert(:user, scheduled_deletion: DateTime.utc_now())
      token = Lightning.Accounts.generate_api_token(user)

      assert {:error, :user_blocked} = Tokens.verify(token)
    end

    test "get_subject resolves the user regardless of account state" do
      user = insert(:user, disabled: true)

      assert Tokens.get_subject(%{"sub" => "user:#{user.id}"}) ==
               Repo.reload!(user)
    end

    test "rejects a PAT whose persisted token row has been deleted" do
      user = insert(:user)
      token = Lightning.Accounts.generate_api_token(user)

      assert {:ok, %{"sub" => "user:" <> _}} = Tokens.verify(token)

      user_token = Repo.get_by(Lightning.Accounts.UserToken, token: token)
      {:ok, _} = Lightning.Accounts.delete_token(user_token)

      assert {:error, :token_revoked} = Tokens.verify(token)
    end

    # A credential_transfer sub is neither "user:" nor "run:", so it falls
    # through to the unsupported branch without touching the store.
    test "an unsupported token type is rejected" do
      {:ok, token, _claims} =
        Tokens.PersonalAccessToken.generate_and_sign(
          %{"sub" => "credential_transfer:#{Ecto.UUID.generate()}"},
          Lightning.Config.token_signer()
        )

      assert {:error, "Unsupported token type"} = Tokens.verify(token)
    end

    test "deleting one user's token leaves another user's token valid" do
      user_a = insert(:user)
      user_b = insert(:user)

      token_a = Lightning.Accounts.generate_api_token(user_a)
      token_b = Lightning.Accounts.generate_api_token(user_b)

      user_token_a = Repo.get_by(Lightning.Accounts.UserToken, token: token_a)
      {:ok, _} = Lightning.Accounts.delete_token(user_token_a)

      assert {:error, _reason} = Tokens.verify(token_a)
      assert {:ok, %{"sub" => "user:" <> _}} = Tokens.verify(token_b)
    end
  end

  describe "RunToken" do
    test "verify a valid token" do
      Lightning.Stub.freeze_time(~U[2024-01-01 00:00:00Z])

      token =
        Lightning.Workers.generate_run_token(%{
          id: run_id = Ecto.UUID.generate()
        })

      assert {:ok, claims} = Tokens.verify(token)

      assert %{
               "exp" => 1_704_067_270,
               "id" => run_id,
               "iss" => "Lightning",
               "nbf" => 1_704_067_200,
               "sub" => "run:#{run_id}"
             } == claims
    end

    test "verify a forged/invalid token" do
      token =
        Lightning.Workers.generate_run_token(%{id: Ecto.UUID.generate()})

      replace_signer(:run_token_signer)

      assert {:error, :signature_error} = Tokens.verify(token)
    end

    test "verify an expired token" do
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
