defmodule Lightning.TokenHelpers do
  @moduledoc """
  Mints tokens in the shapes that actually cross the wire, and names the shapes
  a refusal is allowed to take.

  `WorkerToken.generate_and_sign/2` runs the module's claim generators, and Joken
  merges supplied claims over generated ones — so a token that omits a configured
  claim cannot be produced through it. `@openfn/ws-worker` has never sent `nbf`,
  which is exactly the claim that module generates, so tests built on it exercise
  a shape no worker has ever emitted.
  """

  import ExUnit.Assertions

  @doc """
  The claim set `@openfn/ws-worker` 1.27.4 mints: `worker_id`, `iat`, `iss` and
  nothing else.

  See `packages/ws-worker/src/util/worker-token.ts:6-34` in the kit repo.
  """
  def ws_worker_claims(overrides \\ %{}) do
    %{
      "worker_id" => "curly-parrot-jumps",
      "iat" => DateTime.to_unix(Lightning.current_time()),
      "iss" => "urn:openfn:worker"
    }
    |> Map.merge(overrides)
  end

  @doc """
  A worker token shaped exactly like `@openfn/ws-worker` 1.27.4's:
  `worker_id`, `iat`, `iss` and nothing else.

  Pass `overrides` to change one thing about a token that is otherwise exactly
  what ws-worker sends, so a refusal test and its positive control run off the
  same builder.
  """
  def ws_worker_token(overrides \\ %{}) do
    overrides
    |> ws_worker_claims()
    |> raw_worker_token()
  end

  @doc """
  A worker token carrying exactly the claims given — no generators, nothing
  added. Use it to build a token that is *missing* a claim ws-worker sends.
  """
  def raw_worker_token(claims) do
    sign(claims, Lightning.Config.worker_token_signer())
  end

  @doc """
  A run token carrying exactly the claims given — no generators, nothing added.

  Takes the signer so a wrong-key forgery can be built with the same helper.
  """
  def raw_run_token(claims, signer \\ nil) do
    sign(claims, signer || Lightning.Config.run_token_signer())
  end

  @doc "The claim set a genuine `generate_run_token/2` mint produces, for a given run id."
  def valid_run_claims(run_id, overrides \\ %{}) do
    now = DateTime.to_unix(Lightning.current_time())

    %{
      "iss" => "Lightning",
      "id" => run_id,
      "sub" => "run:#{run_id}",
      "nbf" => now,
      # A real mint uses run_timeout_ms + grace, which is 70s at defaults. An hour
      # here so a test that freezes time forward a little does not expire it by
      # accident; override if you are deliberately testing expiry.
      "exp" => now + 3600
    }
    |> Map.merge(overrides)
  end

  @doc """
  A three-segment token with `payload` as its middle segment and something that
  is not a signature as its last.

  Built by hand rather than through Joken because the point is a payload Joken
  will not produce: one that does not base64-decode to JSON, or that decodes to
  a JSON array or string rather than an object. `Joken.peek_claims/1` raises on
  the first and returns a bare list or string for the others, so both shapes
  have to reach a verifier for its guard to mean anything.
  """
  def jwt_with_payload(payload) do
    header = Base.url_encode64(~s({"alg":"RS256","typ":"JWT"}), padding: false)

    Enum.join(
      [header, Base.url_encode64(payload, padding: false), "signature"],
      "."
    )
  end

  @doc """
  Unwraps an accepted result and returns its payload, or flunks with `message`
  naming what refused it.

  `assert {:ok, claims} = result, message` cannot do this job: `assert/2` is a
  function, so the match is evaluated first and its `MatchError` is raised before
  the message is ever read.
  """
  def assert_accepted(result, message) do
    case result do
      {:ok, payload} ->
        payload

      other ->
        flunk(message <> " It was refused with #{inspect(other)}.")
    end
  end

  @doc """
  Asserts `result` is a refusal whose reason names one of `claims`.

  Three refusal shapes are legitimate and a correct fix may produce any of them:
  the presence gate's `{:missing_claims, [...]}`, a Joken validator's
  `[message: _, claim: _, claim_val: _]`, and `:nbf_not_reached`, which
  `Workers.transform_error/1` rewrites a run token's `nbf` failure to before it
  leaves the verifier. What is not accepted is a bare `{:error, _}` — that would
  also match `:signature_error` and `:token_malformed`, which are different bugs
  with different fixes.
  """
  def assert_refused_naming(result, claims, message) do
    case result do
      {:error, {:missing_claims, missing}} ->
        assert Enum.any?(missing, &(&1 in claims)),
               message <>
                 " It was refused for missing #{inspect(missing)}, none of which is #{inspect(claims)}."

      {:error, :nbf_not_reached} ->
        assert "nbf" in claims,
               message <>
                 " It was refused for nbf, which is not #{inspect(claims)}."

      {:error, reason} when is_list(reason) ->
        assert Keyword.get(reason, :claim) in claims,
               message <>
                 " It was refused for #{inspect(Keyword.get(reason, :claim))}, which is not #{inspect(claims)}."

      {:ok, accepted} ->
        flunk(message <> " It was accepted, returning #{inspect(accepted)}.")

      other ->
        flunk(
          message <>
            " It was refused with #{inspect(other)}, which names no claim, so this test " <>
            "cannot tell which check caught it."
        )
    end
  end

  # An empty token config generates nothing, so the claim map given is the claim
  # map signed. This deliberately bypasses each token module's own generators,
  # which is the only way to build a token that *omits* a claim the module would
  # otherwise stamp in — `nbf` on a worker token, `iat` on a personal access one.
  defp sign(claims, signer), do: Joken.generate_and_sign!(%{}, claims, signer)
end
