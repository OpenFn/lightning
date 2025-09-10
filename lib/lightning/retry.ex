defmodule Lightning.Retry do
  @moduledoc """
  Retry helpers with exponential backoff and optional jitter.
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

  @type retry_result :: {:ok, any()} | {:error, term()}

  @default_opts [
    max_attempts: 5,
    initial_delay_ms: 100,
    max_delay_ms: 10_000,
    backoff_factor: 2.0,
    timeout_ms: 60_000,
    jitter: true,
    context: %{}
  ]

  @spec with_webhook_retry((-> retry_result), [retry_option()]) :: retry_result
  def with_webhook_retry(fun, opts \\ []) when is_function(fun, 0) do
    final_opts =
      @default_opts
      |> Keyword.merge(Lightning.Config.webhook_retry())
      |> Keyword.merge(opts)

    with_retry(fun, final_opts)
  end

  @spec with_retry((-> retry_result), [retry_option()]) :: retry_result
  def with_retry(fun, opts \\ []) when is_function(fun, 0) do
    config = build_config(opts)

    start_time = monotonic_ms()
    deadline = start_time + config.timeout_ms

    :telemetry.execute(
      [:lightning, :retry, :start],
      %{attempt: 1},
      config.context
    )

    {result, final_attempt} =
      do_retry(fun, 1, config.initial_delay_ms, deadline, config)

    duration = monotonic_ms() - start_time
    status = if match?({:ok, _}, result), do: :success, else: :failure

    :telemetry.execute(
      [:lightning, :retry, :stop],
      %{attempts: final_attempt, duration_ms: duration},
      Map.put(config.context, :result, status)
    )

    Logger.debug(
      "retry finished: result=#{status} duration_ms=#{duration} ctx=#{inspect(config.context)}"
    )

    result
  end

  @spec retriable_error?(term()) :: boolean()
  def retriable_error?({:error, %DBConnection.ConnectionError{}}), do: true
  def retriable_error?(_), do: false

  defp do_retry(fun, attempt, delay, deadline, config) do
    case call(fun) |> handle_result(attempt, delay, deadline, config) do
      {:continue, next_attempt, next_delay, sleep_ms} ->
        if sleep_ms > 0, do: Process.sleep(sleep_ms)
        do_retry(fun, next_attempt, next_delay, deadline, config)

      {:done, result, final_attempt} ->
        {result, final_attempt}
    end
  end

  defp handle_result(
         {:ok, _} = success,
         attempt,
         _delay,
         _deadline,
         config
       ) do
    if attempt > 1 do
      :telemetry.execute(
        [:lightning, :retry, :succeeded],
        %{attempts: attempt},
        config.context
      )

      Logger.info(
        "retry succeeded after #{attempt} attempts ctx=#{inspect(config.context)}"
      )
    end

    {:done, success, attempt}
  end

  defp handle_result({:error, _} = error, attempt, delay, deadline, config) do
    remaining_time = deadline - monotonic_ms()

    case classify(error, attempt, delay, remaining_time, config) do
      :not_retryable ->
        Logger.debug(
          "retry not retryable attempt=#{attempt} error=#{short_error(error)} ctx=#{inspect(config.context)}"
        )

        {:done, error, attempt}

      :exhausted ->
        :telemetry.execute(
          [:lightning, :retry, :exhausted],
          %{attempts: attempt},
          config.context
        )

        Logger.warning(
          "retry exhausted attempts=#{attempt} error=#{short_error(error)} ctx=#{inspect(config.context)}"
        )

        {:done, error, attempt}

      :timeout ->
        :telemetry.execute(
          [:lightning, :retry, :timeout],
          %{attempts: attempt},
          config.context
        )

        Logger.warning(
          "retry timeout attempts=#{attempt} ctx=#{inspect(config.context)}"
        )

        {:done, error, attempt}

      {:retry, sleep_ms, next_delay} ->
        :telemetry.execute(
          [:lightning, :retry, :attempt],
          %{attempt: attempt, sleep_ms: sleep_ms, next_delay_ms: next_delay},
          config.context
        )

        Logger.debug(
          "retry sleeping attempt=#{attempt} delay_ms=#{sleep_ms} ctx=#{inspect(config.context)}"
        )

        {:continue, attempt + 1, next_delay, sleep_ms}
    end
  end

  defp classify(error, attempt, delay, remaining_time, config) do
    cond do
      not config.retry_on.(error) ->
        :not_retryable

      attempt >= config.max_attempts ->
        :exhausted

      remaining_time <= 0 ->
        :timeout

      true ->
        sleep_ms =
          calculate_next_delay(delay, config)
          |> min(remaining_time)
          |> to_int()

        {:retry, sleep_ms, next_base_delay(delay, config)}
    end
  end

  defp next_base_delay(delay, config) do
    delay
    |> Kernel.*(config.backoff_factor)
    |> trunc()
    |> min(config.max_delay_ms)
  end

  defp call(fun) do
    fun.()
  rescue
    e in DBConnection.ConnectionError ->
      # retryable; becomes tuple
      {:error, e}

    e ->
      # NOT retryable; preserve original behavior
      reraise e, __STACKTRACE__
  end

  defp build_config(opts) do
    merged = Keyword.merge(@default_opts, opts)

    %{
      max_attempts: merged[:max_attempts] |> to_int() |> max(1),
      initial_delay_ms: merged[:initial_delay_ms] |> to_int() |> max(0),
      max_delay_ms:
        merged[:max_delay_ms]
        |> to_int()
        |> max(merged[:initial_delay_ms] |> to_int()),
      backoff_factor: merged[:backoff_factor] |> to_float() |> max(1.0),
      timeout_ms: merged[:timeout_ms] |> to_int() |> max(0),
      retry_on: merged[:retry_on] || (&default_retry_check/1),
      context: merged[:context] || %{},
      jitter: !!merged[:jitter]
    }
  end

  defp calculate_next_delay(base_delay, %{jitter: true}) when base_delay > 0 do
    max_jitter = div(base_delay, 4)
    jitter = if max_jitter > 0, do: :rand.uniform(max_jitter) - 1, else: 0
    base_delay + jitter
  end

  defp calculate_next_delay(base_delay, _), do: base_delay

  defp default_retry_check({:error, %DBConnection.ConnectionError{}}), do: true
  defp default_retry_check(_), do: false

  defp monotonic_ms, do: System.monotonic_time(:millisecond)

  defp to_int(v) when is_integer(v), do: v
  defp to_int(v) when is_float(v), do: trunc(v)

  defp to_int(v) when is_binary(v) do
    case Integer.parse(v) do
      {i, _} -> i
      :error -> 0
    end
  end

  defp to_int(_), do: 0

  defp to_float(v) when is_float(v), do: v
  defp to_float(v) when is_integer(v), do: v / 1.0

  defp to_float(v) when is_binary(v) do
    case Float.parse(v) do
      {f, _} -> f
      :error -> 0.0
    end
  end

  defp to_float(_), do: 0.0

  defp short_error({:error, e}) when is_struct(e), do: Exception.message(e)
  defp short_error(other), do: inspect(other)
end
