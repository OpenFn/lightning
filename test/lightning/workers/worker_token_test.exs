defmodule Lightning.Workers.WorkerTokenTest do
  @moduledoc """
  What `Workers.verify_worker_token/2` accepts from deployed workers, and what
  it refuses. The generator's own tests live in `workers_test.exs`.
  """

  use ExUnit.Case, async: true

  import Lightning.TokenHelpers

  alias Lightning.Workers

  setup do
    Mox.stub_with(LightningMock, Lightning.API)
    Mox.stub_with(Lightning.MockConfig, Lightning.Config.API)

    :ok
  end

  describe "verify_worker_token/2" do
    # THE ws-worker compatibility guard — with its twin on WorkerSocket.connect/2 in
    # worker_socket_test.exs, the most important test in this suite. A real
    # worker token carries worker_id, iat and iss and NO nbf, so `nbf` must never
    # join @worker_token_claims: requiring it goes green in CI, because every
    # other worker-token fixture is minted through generate_and_sign/2 which
    # stamps nbf in, and disconnects every worker in the field on deploy.
    test "accepts a token shaped exactly like @openfn/ws-worker 1.27.4's" do
      claims =
        ws_worker_token()
        |> Workers.verify_worker_token()
        |> assert_accepted(
          "verify_worker_token/2 refused the exact claim set every worker in the field " <>
            "sends. Shipping this disconnects every deployed worker."
        )

      assert %{
               "worker_id" => "curly-parrot-jumps",
               "iss" => "urn:openfn:worker",
               "iat" => _
             } = claims

      # The other half of the guard: the token that was just accepted carries no
      # nbf at all. This is the fact a future tidy-up would have to break.
      refute Map.has_key?(claims, "nbf")
    end

    test "rejects an empty claim set signed with the worker secret" do
      assert_ws_worker_control("the empty-claim-set case")

      %{}
      |> raw_worker_token()
      |> Workers.verify_worker_token()
      |> assert_refused_naming(
        ~w(iss iat worker_id),
        "verify_worker_token/2 accepted a token with no claims at all. The resulting " <>
          "claims: %{} still satisfies RunChannel.join/3's not is_nil(worker_claims) guard."
      )
    end

    test "rejects a pre-1.0 worker's issuer" do
      assert_ws_worker_control("the pre-1.0 issuer case")

      %{"iss" => "urn:example:issuer"}
      |> ws_worker_token()
      |> Workers.verify_worker_token()
      |> assert_refused_naming(
        ["iss"],
        "verify_worker_token/2 accepted a token issued by urn:example:issuer, which no " <>
          "worker has sent since ws-worker 1.0."
      )
    end

    test "rejects a token missing any one of the claims ws-worker sends" do
      assert_ws_worker_control("each missing-claim case below")

      for claim <- ~w(iss iat worker_id) do
        ws_worker_claims()
        |> Map.delete(claim)
        |> raw_worker_token()
        |> Workers.verify_worker_token()
        |> assert_refused_naming(
          [claim],
          "verify_worker_token/2 accepted a worker token with no #{claim} claim, so " <>
            "verification reduces to the HS256 signature check."
        )
      end
    end

    test "accepts a token carrying an extra, unrecognised claim" do
      claims =
        %{"capabilities" => ["x"]}
        |> ws_worker_token()
        |> Workers.verify_worker_token()
        |> assert_accepted(
          "verify_worker_token/2 refused a worker token carrying an extra claim, so a " <>
            "ws-worker release that adds one would break every instance not yet upgraded."
        )

      assert %{"capabilities" => ["x"]} = claims
    end

    # Distinct from the ws-worker guard above: ws-worker sends no nbf, so retaining
    # the nbf validator costs nothing — but it must still fire when one is sent.
    test "rejects a token whose nbf has not been reached" do
      assert_ws_worker_control("the future-nbf case")

      not_yet = DateTime.to_unix(Lightning.current_time()) + 5

      %{"nbf" => not_yet}
      |> ws_worker_token()
      |> Workers.verify_worker_token()
      |> assert_refused_naming(
        ["nbf"],
        "verify_worker_token/2 accepted a worker token that is not yet valid."
      )
    end

    # The twin of the non-string case in workers_test.exs. `connect/2` only ever
    # hands this a query-string value, so it is binary in practice — the point is
    # that the tagged-tuple contract holds for every input, for the next caller.
    test "rejects a token param that is not a string at all" do
      assert_ws_worker_control("the non-string cases below")

      for token <- [nil, 123, %{"alg" => "none"}, ["a", "b"], true] do
        assert Workers.verify_worker_token(token) == {:error, :token_malformed},
               "verify_worker_token/2 must refuse #{inspect(token)} with :token_malformed " <>
                 "rather than raising."
      end
    end
  end

  # Pairs every refutation above with the same builder, the one bad thing
  # corrected. Without it a refusal could just mean the worker signer or the
  # fixture is broken.
  defp assert_ws_worker_control(what) do
    ws_worker_token()
    |> Workers.verify_worker_token()
    |> assert_accepted(
      "positive control for #{what}: the unmodified ws-worker claim set was refused, so " <>
        "that refusal says nothing about what the test changed."
    )
  end
end
