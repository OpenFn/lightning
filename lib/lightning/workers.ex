defmodule Lightning.Workers do
  @moduledoc """
  Lightning uses external worker processes to execute workflow jobs.

  This module deals with the security tokens and the formatting used on
  the communication with the workers.
  """
  defmodule WorkerToken do
    @moduledoc """
    JWT token configuration to authenticate workers.
    """
    use Joken.Config

    @impl true
    def token_config do
      %{}
      |> add_claim(
        "iss",
        fn -> "urn:openfn:worker" end,
        &(&1 == "urn:openfn:worker")
      )
      # `@openfn/ws-worker` has never sent `nbf` — it mints `worker_id`, `iat`
      # and `iss`, and nothing else. So this validator never fires against a
      # real worker token, and it is kept only so that one which does send `nbf`
      # gets checked. `nbf` must never be added to `@worker_token_claims`:
      # requiring it passes CI, because every test here mints through
      # `generate_and_sign/2` which stamps it in, and disconnects every worker
      # in the field.
      |> add_claim(
        "nbf",
        fn -> Lightning.current_time() |> DateTime.to_unix() end,
        fn nbf, _claims, %{current_time: current_time} ->
          current_time |> DateTime.to_unix() >= nbf
        end
      )
    end
  end

  defmodule RunToken do
    @moduledoc """
    JWT token configuration to verify if workers work is legit.

    Verify run tokens through `Lightning.Workers.verify_run_token/2`, never
    through `verify_and_validate/3` here. Joken looks up a validator per claim
    the *token* carries, so the `exp` and `sub` checks below do not run for a
    token that simply omits them; `verify_run_token/2` is where the claims are
    required to be present, and so is the only place those two checks bind.
    """
    use Joken.Config

    @impl true
    def token_config do
      %{}
      |> add_claim("iss", fn -> "Lightning" end, &(&1 == "Lightning"))
      |> add_claim("id", nil, fn id, _claims, context ->
        Map.get(context, :id)
        |> case do
          nil ->
            is_binary(id)

          expected_id ->
            is_binary(id) and id == expected_id
        end
      end)
      |> add_claim(
        "nbf",
        fn -> Lightning.current_time() |> DateTime.to_unix() end,
        fn nbf, _claims, %{current_time: current_time} ->
          current_time |> DateTime.to_unix() >= nbf
        end
      )
      # `is_number/1` is what makes the comparison mean anything: Erlang orders
      # numbers below every other type, so an `exp` of `nil`, `"soon"` or `true`
      # is "greater than" any timestamp and the token never expires. Numbers
      # rather than integers because RFC 7519 NumericDate permits a fractional
      # value, and refusing one would read as an expired token that has not.
      |> add_claim(
        "exp",
        nil,
        fn exp, _claims, %{current_time: current_time} ->
          is_number(exp) and current_time |> DateTime.to_unix() < exp
        end
      )
      # Cross-checked against `id` rather than merely prefix-matched, so a token
      # whose `sub` and `id` name different runs is refused. The generator is
      # `nil` because `generate_run_token/2` supplies `sub` explicitly.
      |> add_claim("sub", nil, fn sub, claims, _context ->
        is_binary(sub) and is_binary(claims["id"]) and
          sub == "run:" <> claims["id"]
      end)
    end
  end

  @spec generate_run_token(
          Lightning.Run.t(),
          Lightning.Runs.RunOptions.t()
        ) :: binary()
  def generate_run_token(run, run_options \\ %Lightning.Runs.RunOptions{}) do
    {:ok, token, _claims} =
      RunToken.generate_and_sign(
        %{
          "id" => run.id,
          "exp" => calculate_token_expiry(run_options.run_timeout_ms),
          "sub" => "run:#{run.id}"
        },
        Lightning.Config.run_token_signer()
      )

    token
  end

  defp calculate_token_expiry(run_timeout_ms) do
    Lightning.current_time()
    |> DateTime.add(run_timeout_ms, :millisecond)
    |> DateTime.add(Lightning.Config.grace_period())
    |> DateTime.to_unix()
  end

  # Claims a genuine mint always produces. A claim config cannot make a claim
  # mandatory on its own — Joken walks the token's claims, not the config — so
  # absence is what these guard against.
  @run_token_claims ~w(iss id nbf exp sub)

  # Exactly what `@openfn/ws-worker` has sent since 1.0 (Feb 2024). `nbf` does
  # not belong here; see the comment on `WorkerToken.token_config/0`.
  @worker_token_claims ~w(iss iat worker_id)

  @doc """
  Verifies and validates a run token.

  It requires a context map with the following keys:

  - `:id` - the run id that the token was issued with.

  Optionally takes a context map that will be passed to the validation:

  - `:current_time` - the current time as a `DateTime` struct.
  """
  @spec verify_run_token(term(), map()) ::
          {:ok, Joken.claims()} | {:error, any()}
  # `RunChannel.join/3` matches `%{"token" => token}` on a decoded JSON payload,
  # so `token` can be any JSON value. Without this clause a number, null, an
  # object or an array crashes the channel instead of being refused.
  def verify_run_token(token, _context) when not is_binary(token),
    do: {:error, :token_malformed}

  def verify_run_token(token, context) when is_binary(token) do
    context = Enum.into(context, %{current_time: Lightning.current_time()})

    with :ok <- Lightning.Tokens.require_claims(token, @run_token_claims),
         {:ok, claims} <-
           RunToken.verify_and_validate(
             token,
             Lightning.Config.run_token_signer(),
             context
           ) do
      {:ok, claims}
    else
      {:error, error} -> {:error, transform_error(error)}
    end
  end

  @doc """
  Verifies and validates a worker token.

  Optionally takes a context map that will be passed to the validation:

  - `:current_time` - the current time as a `DateTime` struct.
  """
  @spec verify_worker_token(term(), map()) ::
          {:ok, Joken.claims()} | {:error, any()}
  def verify_worker_token(token, context \\ %{})

  def verify_worker_token(token, _context) when not is_binary(token),
    do: {:error, :token_malformed}

  def verify_worker_token(token, context) when is_binary(token) do
    context = Enum.into(context, %{current_time: Lightning.current_time()})

    with :ok <- Lightning.Tokens.require_claims(token, @worker_token_claims) do
      WorkerToken.verify_and_validate(
        token,
        Lightning.Config.worker_token_signer(),
        context
      )
    end
  end

  defp transform_error({:missing_claims, _claims} = error) do
    error
  end

  defp transform_error(error) when is_atom(error) do
    error
  end

  defp transform_error(error) when is_list(error) do
    error
    |> Keyword.get(:claim)
    |> case do
      "nbf" ->
        :nbf_not_reached

      _other ->
        error
    end
  end
end
