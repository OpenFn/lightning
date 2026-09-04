defmodule Lightning.WorkersTest do
  use ExUnit.Case, async: true

  import Lightning.TokenHelpers

  alias Lightning.Runs.RunOptions
  alias Lightning.Tokens
  alias Lightning.Workers
  alias Lightning.Workers.RunToken
  alias Lightning.Workers.WorkerToken

  setup do
    Mox.stub_with(LightningMock, Lightning.API)
    Mox.stub_with(Lightning.MockConfig, Lightning.Config.API)

    %{run_token_signer: Lightning.Config.run_token_signer()}
  end

  describe "WorkerToken" do
    test "can generate a token" do
      {:ok, token, claims} =
        WorkerToken.generate_and_sign(%{"id" => id = Ecto.UUID.generate()})

      assert %{"id" => ^id, "nbf" => nbf} = claims
      assert nbf <= Lightning.current_time() |> DateTime.to_unix()
      assert token != ""

      assert {:ok, claims} = WorkerToken.verify(token)

      assert {:error,
              [
                {:message, "Invalid token"},
                {:claim, "nbf"},
                {:claim_val, _time}
              ]} =
               WorkerToken.validate(claims, %{
                 current_time: DateTime.utc_now() |> DateTime.add(-5, :second)
               })
    end
  end

  describe "RunToken" do
    test "can generate a token", %{run_token_signer: run_token_signer} do
      {:ok, token, claims} =
        RunToken.generate_and_sign(
          %{"id" => id = Ecto.UUID.generate()},
          run_token_signer
        )

      assert %{"id" => ^id, "nbf" => nbf} = claims
      assert nbf <= Lightning.current_time() |> DateTime.to_unix()
      assert token != ""

      assert {:ok, ^claims} =
               RunToken.verify(token, run_token_signer)
    end

    test "validating with a run_id" do
      {:ok, claims} =
        RunToken.generate_claims(%{"id" => id = Ecto.UUID.generate()})

      assert {:ok, ^claims} =
               RunToken.validate(claims, %{
                 id: id,
                 current_time: Lightning.current_time()
               })
    end

    test "validating without a run_id" do
      {:ok, claims} =
        RunToken.generate_claims(%{"id" => _id = Ecto.UUID.generate()})

      assert {:ok, ^claims} =
               RunToken.validate(claims, %{
                 current_time: Lightning.current_time()
               })
    end
  end

  describe "verify_run_token/2 rejects tokens that are not run tokens" do
    setup do
      %{
        user_id: Ecto.UUID.generate(),
        run: %Lightning.Run{id: Ecto.UUID.generate()}
      }
    end

    test "a personal access token", %{user_id: user_id} do
      user_id
      |> genuine_pat()
      |> Workers.verify_run_token(%{id: Ecto.UUID.generate()})
      |> assert_refused_naming(
        ~w(id nbf exp sub),
        "verify_run_token/2 accepted a personal access token for an arbitrary run id: " <>
          "any user holding a PAT can join run:<id> and fetch that run's credentials and dataclip."
      )
    end

    test "a personal access token, with no run id in the context", %{
      user_id: user_id
    } do
      user_id
      |> genuine_pat()
      |> Workers.verify_run_token(%{})
      |> assert_refused_naming(
        ~w(id nbf exp sub),
        "verify_run_token/2 accepted a personal access token on the empty-context path " <>
          "that Tokens.verify/1 uses, so a PAT authorises as a run token there too."
      )
    end

    test "a credential transfer token" do
      genuine_credential_transfer_token()
      |> Workers.verify_run_token(%{id: Ecto.UUID.generate()})
      |> assert_refused_naming(
        ~w(id nbf sub),
        "verify_run_token/2 accepted a credential transfer token as a run token."
      )
    end

    test "a run token whose sub and id name different runs", %{run: run} do
      claims = valid_run_claims(run.id)

      assert_run_control(claims, run.id, "the sub/id cross-check")

      claims
      |> Map.put("sub", "run:#{Ecto.UUID.generate()}")
      |> raw_run_token()
      |> Workers.verify_run_token(%{id: run.id})
      |> assert_refused_naming(
        ~w(sub id),
        "verify_run_token/2 accepted a run token whose sub names a different run to its id, " <>
          "so the sub claim carries no authority at all."
      )
    end

    test "a run token missing any one of the claims a genuine mint produces", %{
      run: run
    } do
      claims = valid_run_claims(run.id)

      assert_run_control(claims, run.id, "each missing-claim case below")

      for claim <- ~w(iss id nbf exp sub) do
        claims
        |> Map.delete(claim)
        |> raw_run_token()
        |> Workers.verify_run_token(%{id: run.id})
        |> assert_refused_naming(
          [claim],
          "verify_run_token/2 accepted a run token with no #{claim} claim. " <>
            "Joken skips the validator for an absent claim, so dropping a claim removes its check."
        )
      end
    end

    # The presence gate has to peek at unverified claims, and
    # Joken.peek_claims/1 raises or returns a non-map on these five, so an
    # unguarded peek would turn a clean refusal into a crash on the run channel.
    test "a malformed token string, with a reason rather than a crash", %{
      run: run
    } do
      malformed = [
        {"a token with an unparseable payload", "aaa.bbb.ccc"},
        {"a payload that is not JSON", jwt_with_payload("notjson")},
        {"a payload that is a JSON array", jwt_with_payload("[1,2,3]")},
        {"a payload that is a JSON string", jwt_with_payload(~s("hi"))},
        {"a string that is not a JWT at all", "not-a-jwt"}
      ]

      for {label, token} <- malformed do
        assert Workers.verify_run_token(token, %{id: run.id}) ==
                 {:error, :token_malformed},
               "verify_run_token/2 must refuse #{label} with :token_malformed. " <>
                 "RunChannel.join/3 hands it the client's token param verbatim, so this is " <>
                 "attacker-controlled input on the surface being hardened."
      end

      # Positive control off the same builder: a payload that *is* a JSON object
      # carrying every required claim gets past the presence gate and is refused
      # for its signature instead. Without it, :token_malformed above could just
      # mean jwt_with_payload/1 cannot build anything a verifier will look at.
      well_formed =
        run.id |> valid_run_claims() |> Jason.encode!() |> jwt_with_payload()

      assert Workers.verify_run_token(well_formed, %{id: run.id}) ==
               {:error, :signature_error},
             "positive control: a well-formed claims payload was refused as malformed, " <>
               "so the malformed cases above say nothing about the payload being unreadable."
    end

    # `RunChannel.join/3` matches `%{"token" => token}` against a decoded JSON
    # payload, so the token param is whatever the client put there. These five
    # used to raise FunctionClauseError against the `is_binary(token)` guard,
    # which crashes the channel process rather than refusing the join.
    test "a token param that is not a string at all", %{run: run} do
      assert_run_control(
        valid_run_claims(run.id),
        run.id,
        "the non-string cases below"
      )

      for token <- [nil, 123, %{"alg" => "none"}, ["a", "b"], true] do
        assert Workers.verify_run_token(token, %{id: run.id}) ==
                 {:error, :token_malformed},
               "verify_run_token/2 must refuse #{inspect(token)} with :token_malformed " <>
                 "rather than raising. Every input reaching it is attacker-chosen, and a " <>
                 "raise here is a crashed channel plus a Sentry event per attempt."
      end
    end
  end

  describe "verify_run_token/2 accepts genuine run tokens" do
    setup do
      %{run: %Lightning.Run{id: Ecto.UUID.generate()}}
    end

    test "a genuine token for the run it names", %{run: run} do
      claims =
        run
        |> Workers.generate_run_token(%RunOptions{})
        |> Workers.verify_run_token(%{id: run.id})
        |> assert_accepted(
          "verify_run_token/2 refused a token it had just minted for this very run, so " <>
            "no worker can join its own run channel."
        )

      run_id = run.id
      expected_sub = "run:#{run.id}"

      assert %{"iss" => "Lightning", "id" => ^run_id, "sub" => ^expected_sub} =
               claims
    end

    test "not a genuine token presented for a different run", %{run: run} do
      token = Workers.generate_run_token(run, %RunOptions{})

      token
      |> Workers.verify_run_token(%{id: run.id})
      |> assert_accepted(
        "positive control: this token does not verify for its own run, so refusing it " <>
          "for another run proves nothing about the id claim."
      )

      token
      |> Workers.verify_run_token(%{id: Ecto.UUID.generate()})
      |> assert_refused_naming(
        ["id"],
        "verify_run_token/2 accepted run A's token for run B, so the id claim no longer " <>
          "binds a run token to one run."
      )
    end

    test "a token carrying an extra, unrecognised claim", %{run: run} do
      claims =
        run.id
        |> valid_run_claims(%{"capabilities" => ["x"]})
        |> raw_run_token()
        |> Workers.verify_run_token(%{id: run.id})
        |> assert_accepted(
          "verify_run_token/2 refused a run token carrying an extra claim. " <>
            "Requiring claims to be present must never become rejecting unknown ones, " <>
            "or the next ws-worker release breaks every instance that upgrades workers first."
        )

      assert %{"capabilities" => ["x"]} = claims
    end

    test "not a token whose exp is not a number", %{run: run} do
      claims = valid_run_claims(run.id)

      assert_run_control(claims, run.id, "the non-numeric exp case")

      for exp <- [nil, "soon", true, %{}, []] do
        claims
        |> Map.put("exp", exp)
        |> raw_run_token()
        |> Workers.verify_run_token(%{id: run.id})
        |> assert_refused_naming(
          ["exp"],
          "verify_run_token/2 accepted a run token whose exp is #{inspect(exp)}. Erlang " <>
            "sorts every non-number above every number, so `now < exp` is true forever " <>
            "and the token never expires."
        )
      end
    end

    test "a token whose exp carries fractional seconds", %{run: run} do
      claims = valid_run_claims(run.id)

      assert_run_control(claims, run.id, "the fractional exp case")

      claims
      |> Map.put("exp", claims["exp"] + 0.5)
      |> raw_run_token()
      |> Workers.verify_run_token(%{id: run.id})
      |> assert_accepted(
        "verify_run_token/2 refused a run token whose exp carries fractional seconds. " <>
          "RFC 7519 NumericDate permits them, and refusing one reads as an expired " <>
          "token that has an hour left."
      )
    end

    test "not a token five seconds before its nbf", %{run: run} do
      claims = valid_run_claims(run.id)

      assert_run_control(claims, run.id, "the early-nbf case")

      claims
      |> Map.put("nbf", DateTime.to_unix(Lightning.current_time()) + 5)
      |> raw_run_token()
      |> Workers.verify_run_token(%{id: run.id})
      |> assert_refused_naming(
        ["nbf"],
        "verify_run_token/2 accepted a run token five seconds before its nbf, so a " <>
          "token minted for a run that has not started yet already authorises."
      )
    end

    test "not a token signed with the wrong key", %{run: run} do
      claims = valid_run_claims(run.id)

      assert_run_control(claims, run.id, "the wrong-key case")

      {pem, _pub} = Lightning.Utils.Crypto.generate_rsa_key_pair()
      wrong_signer = Joken.Signer.create("RS256", %{"pem" => pem})

      assert Workers.verify_run_token(
               raw_run_token(claims, wrong_signer),
               %{id: run.id}
             ) == {:error, :signature_error},
             "verify_run_token/2 must still reject a forged signature, and say so. " <>
               "A missing-claims reason here would mean the presence gate is shadowing " <>
               "signature verification."
    end
  end

  # Mints a personal access token and proves it is a working one before handing
  # it over, so "verify_run_token/2 refused it" cannot quietly mean the fixture
  # was never a valid token to begin with.
  defp genuine_pat(user_id) do
    token =
      Tokens.PersonalAccessToken.generate_and_sign!(
        %{"sub" => "user:#{user_id}"},
        Lightning.Config.token_signer()
      )

    Tokens.PersonalAccessToken.verify_and_validate(
      token,
      Lightning.Config.token_signer()
    )
    |> assert_accepted(
      "positive control: the fixture is not a valid personal access token, so the " <>
        "run-token refusal built on it proves nothing."
    )

    token
  end

  defp genuine_credential_transfer_token do
    {:ok, token, _claims} =
      Tokens.CredentialTransferToken.generate_and_sign(
        %{"sub" => "credential_transfer:#{Ecto.UUID.generate()}"},
        Lightning.Config.token_signer()
      )

    Tokens.CredentialTransferToken.verify_and_validate(
      token,
      Lightning.Config.token_signer()
    )
    |> assert_accepted(
      "positive control: the fixture is not a valid credential transfer token, so the " <>
        "run-token refusal built on it proves nothing."
    )

    token
  end

  # Pairs a refutation with the same claim set, one bad thing corrected. Both
  # sides run off the caller's `claims`, so they cannot drift apart.
  defp assert_run_control(claims, run_id, what) do
    claims
    |> raw_run_token()
    |> Workers.verify_run_token(%{id: run_id})
    |> assert_accepted(
      "positive control for #{what}: the unmodified claim set was refused, so that " <>
        "refusal says nothing about what the test changed."
    )
  end
end
