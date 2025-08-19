defmodule Lightning.Retry do
  @moduledoc """
  Retry helpers with exponential backoff and optional jitter.

  Intended for transient failures (DB connection hiccups, brief network issues, etc).

  ## Examples

      # Simple database retry
      Retry.with_retry(fn -> Repo.insert(changeset) end)

      # Webhook-friendly config
      Retry.with_webhook_retry(fn -> WorkOrders.create_for(trigger, opts) end)

      # Custom retryable predicate
      Retry.with_retry(fn -> call_api() end,
        retry_on: fn
          {:error, %HTTPoison.Error{reason: :timeout}} -> true
          _ -> false
        end,
        context: %{op: :api_call}
      )
  """

  require Logger

  @type retry_option ::
          {:max_attempts, pos_integer()}
          | {:initial_delay_ms, non_neg_integer()}
          | {:max_delay_ms, non_neg_integer()}
          | {:backoff_factor, number()}
          | {:timeout_ms, non_neg_integer()}
          | {:retry_on, (any() -> boolean())}
          | {:context, map()}
          | {:jitter, boolean()}

  @type config :: %{
          max_attempts: pos_integer(),
          initial_delay_ms: non_neg_integer(),
          max_delay_ms: non_neg_integer(),
          backoff_factor: float(),
          timeout_ms: non_neg_integer(),
          retry_on: (any() -> boolean()),
          context: map(),
          jitter: boolean()
        }

  @default_opts [
    max_attempts: 5,
    initial_delay_ms: 100,
    max_delay_ms: 10_000,
    backoff_factor: 2.0,
    timeout_ms: 60_000,
    jitter: true,
    context: %{}
  ]

  @doc """
  Use configured webhook retry defaults (from `Lightning.Config.webhook_retry/0`)
  merged over library defaults; user `opts` win last.
  """
  @spec with_webhook_retry((-> any()), [retry_option()]) :: any()
  def with_webhook_retry(fun, opts \\ []) when is_function(fun, 0) do
    final_opts =
      @default_opts
      |> Keyword.merge(Lightning.Config.webhook_retry())
      |> Keyword.merge(opts)

    with_retry(fun, final_opts)
  end

  @doc """
  Executes `fun` with exponential backoff + optional jitter until success,
  non-retryable error, attempts exhausted, or total timeout reached.

  Returns the final `{:ok, _}` or `{:error, _}` from `fun`.
  """
  @spec with_retry((-> any()), [retry_option()]) :: any()
  def with_retry(fun, opts \\ []) when is_function(fun, 0) do
    config = build_config(opts)

    start_time = monotonic_ms()
    deadline = start_time + config.timeout_ms

    emit_start(config)

    result = do_retry(fun, 1, config.initial_delay_ms, deadline, config)

    duration = monotonic_ms() - start_time
    emit_stop(result, config, duration)

    result
  end

  @spec build_config([retry_option()]) :: config()
  defp build_config(opts) do
    merged = Keyword.merge(@default_opts, opts)

    max_attempts = merged[:max_attempts] |> to_int() |> max(1)
    initial_ms = merged[:initial_delay_ms] |> to_int() |> max(0)
    max_delay_ms = merged[:max_delay_ms] |> to_int() |> max(initial_ms)
    timeout_ms = merged[:timeout_ms] |> to_int() |> max(0)

    backoff_factor =
      merged[:backoff_factor]
      |> to_float()
      |> max(1.0)

    %{
      max_attempts: max_attempts,
      initial_delay_ms: initial_ms,
      max_delay_ms: max_delay_ms,
      backoff_factor: backoff_factor,
      timeout_ms: timeout_ms,
      retry_on: merged[:retry_on] || (&default_retry_check/1),
      context: merged[:context] || %{},
      jitter: !!merged[:jitter]
    }
  end

  @spec do_retry(
          (-> any()),
          pos_integer(),
          non_neg_integer(),
          non_neg_integer(),
          config()
        ) :: any()
  defp do_retry(fun, attempt, delay, deadline, config) do
    result =
      try do
        fun.()
      rescue
        e ->
          {:error, {:exception, e, __STACKTRACE__}}
      end

    case result do
      {:ok, _} = success ->
        if attempt > 1 do
          Logger.info("retry_succeeded",
            attempts: attempt,
            context: config.context
          )
        end

        success

      error ->
        now = monotonic_ms()
        remaining_time = deadline - now

        cond do
          not config.retry_on.(error) ->
            error

          attempt >= config.max_attempts ->
            Logger.warning("retry_exhausted",
              attempts: attempt,
              context: config.context,
              error: short_error(error)
            )

            emit_exhausted(attempt, error, config)
            error

          remaining_time <= 0 ->
            Logger.warning("retry_timeout",
              attempts: attempt,
              context: config.context
            )

            emit_timeout(attempt, config)
            error

          true ->
            next_sleep = calculate_next_delay(delay, config)
            actual_sleep = min(next_sleep, remaining_time) |> to_int()

            Logger.debug("retry_sleep",
              attempt: attempt,
              delay_ms: actual_sleep,
              context: config.context
            )

            emit_attempt(attempt, actual_sleep, error, config)

            if actual_sleep > 0, do: Process.sleep(actual_sleep)

            next_base_delay =
              delay
              |> Kernel.*(config.backoff_factor)
              |> trunc()
              |> min(config.max_delay_ms)

            do_retry(fun, attempt + 1, next_base_delay, deadline, config)
        end
    end
  end

  @spec calculate_next_delay(non_neg_integer(), config()) :: non_neg_integer()
  defp calculate_next_delay(base_delay, %{jitter: true}) when base_delay > 0 do
    max_jitter = div(base_delay, 4)
    jitter = if max_jitter > 0, do: :rand.uniform(max_jitter) - 1, else: 0
    base_delay + jitter
  end

  defp calculate_next_delay(base_delay, _config), do: base_delay

  @spec default_retry_check(any()) :: boolean()
  defp default_retry_check({:error, %DBConnection.ConnectionError{}}), do: true

  defp default_retry_check(
         {:error, {:exception, %DBConnection.ConnectionError{}, _}}
       ),
       do: true

  defp default_retry_check(_), do: false

  @retry_ns [:lightning, :retry]

  @spec emit(atom(), map(), map()) :: :ok
  defp emit(event, measurements, metadata) when is_atom(event) do
    :telemetry.execute(@retry_ns ++ [event], measurements, metadata)
    :ok
  end

  @spec emit_start(config()) :: :ok
  defp emit_start(config) do
    emit(:start, %{system_time: System.system_time()}, config.context)
  end

  @spec emit_stop({:ok, any()} | {:error, any()}, config(), non_neg_integer()) ::
          :ok
  defp emit_stop(result, config, duration) do
    status = if match?({:ok, _}, result), do: :success, else: :failure
    emit(:stop, %{duration: duration}, Map.put(config.context, :result, status))
  end

  @spec emit_attempt(pos_integer(), non_neg_integer(), any(), config()) :: :ok
  defp emit_attempt(attempt, delay_ms, error, config) do
    emit(
      :attempt,
      %{attempt: attempt, delay_ms: delay_ms},
      Map.merge(config.context, %{error: short_error(error)})
    )
  end

  @spec emit_exhausted(pos_integer(), any(), config()) :: :ok
  defp emit_exhausted(attempts, error, config) do
    emit(
      :exhausted,
      %{attempts: attempts},
      Map.merge(config.context, %{error: short_error(error)})
    )
  end

  @spec emit_timeout(pos_integer(), config()) :: :ok
  defp emit_timeout(attempts, config) do
    emit(:timeout, %{attempts: attempts}, config.context)
  end

  @spec monotonic_ms() :: non_neg_integer()
  defp monotonic_ms, do: System.monotonic_time(:millisecond)

  @spec to_int(term()) :: integer()
  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_float(v), do: trunc(v)

  defp to_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      :error -> 0
    end
  end

  defp to_int(_), do: 0

  @spec to_float(term()) :: float()
  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v / 1.0

  defp to_float(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp to_float(_), do: 0.0

  @spec short_error(any()) :: String.t()
  defp short_error({:error, {:exception, e, _}}), do: Exception.message(e)
  defp short_error({:error, e}) when is_struct(e), do: Exception.message(e)
  defp short_error(other), do: inspect(other)
end
