defmodule Lightning.TokensTest do
  use Lightning.DataCase, async: true

  import Lightning.Factories

  import Lightning.TokenHelpers,
    only: [assert_accepted: 2, assert_refused_naming: 3, jwt_with_payload: 1]

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

  # LightningWeb.Plugs.ApiAuth.call/2 hands verify/1 the Authorization header
  # verbatim and its else only matches {:error, _reason}, so a raise here is an
  # unauthenticated 500 on /collections rather than a 401.
  describe "verify/1 with a malformed token" do
    test "a payload that cannot be read is refused with :token_malformed" do
      for {label, token} <- [
            {"three segments that are not base64 JSON", "aaa.bbb.ccc"},
            {"a payload that is not JSON", jwt_with_payload("notjson")},
            {"a string that is not a JWT at all", "not-a-jwt"},
            {"an empty string", ""}
          ] do
        assert Tokens.verify(token) == {:error, :token_malformed},
               "Tokens.verify/1 must refuse #{label} with :token_malformed. " <>
                 "ApiAuth does not catch a raise, so anything else is an " <>
                 "unauthenticated 500 on /collections."
      end
    end

    test "a payload that is JSON but not an object is refused" do
      # Both refusals are correct here — the peek succeeds and returns a bare
      # list or string, which either the malformed guard or the unsupported-type
      # catch-all may claim. What must not happen is a raise, because Map
      # operations downstream have no clause for either shape.
      for {label, token} <- [
            {"a payload that is a JSON array", jwt_with_payload("[1,2,3]")},
            {"a payload that is a JSON string", jwt_with_payload(~s("hi"))}
          ] do
        assert {:error, reason} = Tokens.verify(token),
               "Tokens.verify/1 must refuse #{label} rather than raising on it."

        assert reason in [:token_malformed, "Unsupported token type"],
               "Tokens.verify/1 refused #{label} with #{inspect(reason)}, which is " <>
                 "neither of the refusals this path can legitimately produce."
      end
    end

    test "positive control: a well-formed payload gets past the malformed check" do
      # Same builder as the refusals above, with the one bad thing corrected —
      # the payload is now a JSON object. It reaches signature verification and
      # is refused there, so :token_malformed above is genuinely about the
      # payload being unreadable rather than about the builder producing junk.
      token =
        %{"sub" => "user:#{Ecto.UUID.generate()}"}
        |> Jason.encode!()
        |> jwt_with_payload()

      assert Tokens.verify(token) == {:error, :signature_error},
             "a well-formed claims payload was refused before its signature was " <>
               "checked, so the malformed cases above prove nothing."
    end
  end

  # Asserted against PersonalAccessToken.verify_and_validate/2 rather than
  # Tokens.verify/1: that runs a persisted-row check after validation, and a
  # hand-minted token has no user_tokens row, so it returns :token_revoked
  # whether or not the iat check works.
  describe "PersonalAccessToken iat" do
    test "rejects a token issued in the future" do
      assert_iat_control()

      (DateTime.to_unix(Lightning.current_time()) + 3600)
      |> pat_with_iat()
      |> verify_pat()
      |> assert_refused_naming(
        ["iat"],
        "PersonalAccessToken accepted a token issued an hour in the future, so its iat " <>
          "claim is not being checked at all."
      )
    end

    test "accepts a token issued in the past" do
      past = DateTime.to_unix(Lightning.current_time()) - 3600

      claims =
        past |> pat_with_iat() |> verify_pat() |> assert_accepted(iat_message())

      assert %{"iat" => ^past, "sub" => "user:" <> _} = claims
    end

    test "accepts a token issued a few seconds ahead of this node's clock" do
      assert_iat_control()

      ahead = DateTime.to_unix(Lightning.current_time()) + 5

      claims =
        ahead
        |> pat_with_iat()
        |> verify_pat()
        |> assert_accepted(
          "PersonalAccessToken refused a token issued five seconds ahead. A token is " <>
            "minted on whichever replica served the request and verified on whichever " <>
            "serves the next, so with no tolerance a user is 401'd on a token they have " <>
            "only just created."
        )

      assert %{"iat" => ^ahead} = claims
    end

    test "rejects a token whose iat is not a number" do
      assert_iat_control()

      for iat <- [nil, "now", true, %{}, []] do
        iat
        |> pat_with_iat()
        |> verify_pat()
        |> assert_refused_naming(
          ["iat"],
          "PersonalAccessToken accepted a token whose iat is #{inspect(iat)}. The skew " <>
            "allowance subtracts from iat, so a non-number has to be refused before the " <>
            "arithmetic raises it out of the validator as a 500."
        )
      end
    end
  end

  describe "CredentialTransferToken exp" do
    test "rejects a token whose exp is not a number" do
      assert_transfer_control()

      for exp <- [nil, "soon", true, %{}, []] do
        exp
        |> transfer_token_with_exp()
        |> verify_transfer()
        |> assert_refused_naming(
          ["exp"],
          "CredentialTransferToken accepted a token whose exp is #{inspect(exp)}. Erlang " <>
            "sorts every non-number above every number, so `now < exp` is true forever " <>
            "and the confirmation link never stops working."
        )
      end
    end

    test "accepts a token whose exp carries fractional seconds" do
      assert_transfer_control()

      (DateTime.to_unix(Lightning.current_time()) + 3600.5)
      |> transfer_token_with_exp()
      |> verify_transfer()
      |> assert_accepted(
        "CredentialTransferToken refused a token whose exp carries fractional seconds. " <>
          "RFC 7519 NumericDate permits them, and refusing one makes a confirmation " <>
          "link report itself expired the moment it is sent."
      )
    end

    test "rejects a token that has expired" do
      assert_transfer_control()

      (DateTime.to_unix(Lightning.current_time()) - 3600)
      |> transfer_token_with_exp()
      |> verify_transfer()
      |> assert_refused_naming(
        ["exp"],
        "CredentialTransferToken accepted a token that expired an hour ago."
      )
    end
  end

  # The same builder as the refusals above with an exp an hour out, so a refusal
  # there cannot quietly mean the builder never produced a valid token.
  defp assert_transfer_control do
    (DateTime.to_unix(Lightning.current_time()) + 3600)
    |> transfer_token_with_exp()
    |> verify_transfer()
    |> assert_accepted(
      "positive control: CredentialTransferToken refused a token valid for another hour, " <>
        "so the refusals below say nothing about exp."
    )
  end

  # Signs exactly these claims, bypassing CredentialTransferToken's own exp
  # generator — which would otherwise stamp a real timestamp back in.
  defp transfer_token_with_exp(exp) do
    Joken.generate_and_sign!(
      %{},
      %{
        "iss" => "Lightning",
        "sub" => "credential_transfer:#{Ecto.UUID.generate()}",
        "iat" => DateTime.to_unix(Lightning.current_time()),
        "exp" => exp
      },
      Lightning.Config.token_signer()
    )
  end

  defp verify_transfer(token) do
    Tokens.CredentialTransferToken.verify_and_validate(
      token,
      Lightning.Config.token_signer()
    )
  end

  # The same builder as the refusal above, one hour the other side of now. Both
  # tests run it so neither can be deleted without the other noticing.
  defp assert_iat_control do
    (DateTime.to_unix(Lightning.current_time()) - 3600)
    |> pat_with_iat()
    |> verify_pat()
    |> assert_accepted(iat_message())
  end

  defp iat_message do
    "PersonalAccessToken refused a token issued an hour ago, so the iat check has been " <>
      "tightened past what a real mint produces and every API caller is locked out."
  end

  # An empty token config generates nothing, so this signs exactly these four
  # claims — bypassing PersonalAccessToken's own iat generator, which would
  # otherwise stamp the current time back in.
  defp pat_with_iat(iat) do
    Joken.generate_and_sign!(
      %{},
      %{
        "jti" => Joken.generate_jti(),
        "iss" => "Lightning",
        "sub" => "user:#{Ecto.UUID.generate()}",
        "iat" => iat
      },
      Lightning.Config.token_signer()
    )
  end

  defp verify_pat(token) do
    Tokens.PersonalAccessToken.verify_and_validate(
      token,
      Lightning.Config.token_signer()
    )
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
