# benchmarking/channels/lib/load_test/runner.exs
#
# Executes test scenarios: steady-state, ramp-up, and direct sink.

defmodule LoadTest.Runner do
  @moduledoc false

  @methods [:get, :post, :put, :patch, :delete]

  def run(scenario, channel_url, opts) do
    duration_ms = opts[:duration] * 1_000
    node = String.to_atom(opts[:node])

    # Saturation manages its own memory sampling and returns per-step results
    if scenario == "saturation" do
      run_saturation(channel_url, opts)
    else
      # Start memory sampler in background
      memory_task =
        Task.async(fn -> sample_memory_loop(node, duration_ms) end)

      case scenario do
        "ramp_up" -> run_ramp_up(channel_url, opts, duration_ms)
        _ -> run_steady(scenario, channel_url, opts, duration_ms)
      end

      Task.await(memory_task, :infinity)
    end
  end

  def run_direct(scenario, channel_url, opts) do
    duration_ms = opts[:duration] * 1_000
    # No memory sampling — there is no Lightning BEAM to sample
    run_steady(scenario, channel_url, opts, duration_ms)
  end

  # -- Steady-state scenarios (constant concurrency) --

  defp run_steady(scenario, channel_url, opts, duration_ms) do
    concurrency = opts[:concurrency]
    payload = generate_payload(opts[:payload_size])

    work_stream(duration_ms)
    |> Task.async_stream(
      fn _tick ->
        execute_request(scenario, channel_url, payload, opts)
      end,
      max_concurrency: concurrency,
      timeout: 60_000
    )
    |> Stream.each(fn
      {:ok, {latency_us, status}} ->
        LoadTest.Metrics.record_request(latency_us, status)

      {:exit, reason} ->
        LoadTest.Metrics.record_error(reason)
    end)
    |> Stream.run()
  end

  # -- Ramp-up scenario (increasing concurrency) --

  defp run_ramp_up(channel_url, opts, duration_ms) do
    max_concurrency = opts[:concurrency]
    payload = generate_payload(opts[:payload_size])

    # Divide duration into 10 steps, each at increasing concurrency
    steps = 10
    step_duration_ms = div(duration_ms, steps)

    for step <- 1..steps do
      concurrency = max(1, div(max_concurrency * step, steps))

      IO.puts(
        "  [ramp] Step #{step}/#{steps}: #{concurrency} VUs for #{div(step_duration_ms, 1000)}s"
      )

      work_stream(step_duration_ms)
      |> Task.async_stream(
        fn _tick ->
          execute_request("happy_path", channel_url, payload, opts)
        end,
        max_concurrency: concurrency,
        timeout: 60_000
      )
      |> Stream.each(fn
        {:ok, {latency_us, status}} ->
          LoadTest.Metrics.record_request(latency_us, status)

        {:exit, reason} ->
          LoadTest.Metrics.record_error(reason)
      end)
      |> Stream.run()
    end
  end

  # -- Saturation scenario (increasing concurrency with per-step metrics) --

  @saturation_levels [1, 2, 5, 10, 20, 50, 100, 200, 500, 1000]

  defp run_saturation(channel_url, opts) do
    max_concurrency = opts[:concurrency]
    duration_ms = opts[:duration] * 1_000
    payload = generate_payload(opts[:payload_size])
    node = String.to_atom(opts[:node])

    # Build step sequence: standard levels up to max, always include max
    steps =
      @saturation_levels
      |> Enum.filter(&(&1 <= max_concurrency))
      |> then(fn levels ->
        if max_concurrency in levels,
          do: levels,
          else: levels ++ [max_concurrency]
      end)

    IO.puts("  Steps: #{inspect(steps)}\n")

    # Start memory sampler for the full duration (all steps)
    total_duration_ms = duration_ms * length(steps)

    memory_task =
      Task.async(fn -> sample_memory_loop(node, total_duration_ms) end)

    results =
      steps
      |> Enum.with_index(1)
      |> Enum.map(fn {concurrency, step_num} ->
        # Reset metrics for this step
        LoadTest.Metrics.reset()
        LoadTest.Setup.reset_telemetry_collector(node)

        IO.write(
          "  [saturation] Step #{step_num}/#{length(steps)}: " <>
            "#{concurrency} VUs for #{opts[:duration]}s... "
        )

        # Run the work loop at this concurrency level
        work_stream(duration_ms)
        |> Task.async_stream(
          fn _tick ->
            execute_request("happy_path", channel_url, payload, opts)
          end,
          max_concurrency: concurrency,
          timeout: 60_000
        )
        |> Stream.each(fn
          {:ok, {latency_us, status}} ->
            LoadTest.Metrics.record_request(latency_us, status)

          {:exit, reason} ->
            LoadTest.Metrics.record_error(reason)
        end)
        |> Stream.run()

        # Capture step results
        summary = LoadTest.Metrics.summary()
        telemetry = LoadTest.Setup.get_telemetry_summary(node)

        IO.puts(
          "#{summary.rps} rps, p50=#{format_us_inline(summary.p50)}, " <>
            "#{summary.error_count} errors"
        )

        %{concurrency: concurrency, summary: summary, telemetry: telemetry}
      end)

    Task.await(memory_task, :infinity)
    results
  end

  defp format_us_inline(0), do: "n/a"
  defp format_us_inline(us) when us < 1_000, do: "#{us}us"

  defp format_us_inline(us) when us < 1_000_000,
    do: "#{Float.round(us / 1_000, 1)}ms"

  defp format_us_inline(us), do: "#{Float.round(us / 1_000_000, 2)}s"

  # -- Work stream generator --

  defp work_stream(duration_ms) do
    deadline = System.monotonic_time(:millisecond) + duration_ms

    Stream.repeatedly(fn -> :go end)
    |> Stream.take_while(fn _ ->
      System.monotonic_time(:millisecond) < deadline
    end)
  end

  # -- Request execution --

  defp execute_request(scenario, channel_url, payload, _opts) do
    method = pick_method(scenario)
    start = System.monotonic_time(:microsecond)

    case do_http_request(method, channel_url, payload) do
      {:ok, status} ->
        latency_us = System.monotonic_time(:microsecond) - start
        {latency_us, status}

      {:error, reason} ->
        LoadTest.Metrics.record_error(reason)
        # Return a synthetic latency so the caller does not crash
        latency_us = System.monotonic_time(:microsecond) - start
        {latency_us, :error}
    end
  end

  defp pick_method("happy_path"), do: :post
  defp pick_method("ramp_up"), do: :post
  defp pick_method("saturation"), do: :post
  defp pick_method("large_payload"), do: :post
  defp pick_method("large_response"), do: :get
  defp pick_method("slow_sink"), do: :post
  defp pick_method("direct_sink"), do: :post

  defp pick_method("mixed_methods") do
    Enum.random(@methods)
  end

  defp do_http_request(method, url, payload) do
    body = if method in [:post, :put, :patch], do: payload, else: nil
    headers = [{"content-type", "application/json"}]

    request = Finch.build(method, url, headers, body)

    case Finch.request(request, LoadTest.Finch, receive_timeout: 30_000) do
      {:ok, %Finch.Response{status: status}} -> {:ok, status}
      {:error, reason} -> {:error, reason}
    end
  end

  # -- Payload generation --

  defp generate_payload(size) do
    base =
      Jason.encode!(%{
        timestamp: DateTime.to_iso8601(DateTime.utc_now()),
        source: "load_test"
      })

    base_size = byte_size(base)

    cond do
      base_size >= size ->
        binary_part(base, 0, size)

      true ->
        # Pad with a "data" field to reach the target size
        # Account for the JSON wrapper: {"timestamp":"...","source":"...","data":"PADDING"}
        # We need to rebuild with the padding included
        padding_needed = size - base_size - 11

        padding =
          if padding_needed > 0,
            do: String.duplicate("x", padding_needed),
            else: ""

        result =
          Jason.encode!(%{
            timestamp: DateTime.to_iso8601(DateTime.utc_now()),
            source: "load_test",
            data: padding
          })

        # Trim to exact size if JSON overhead caused overshoot
        if byte_size(result) > size do
          binary_part(result, 0, size)
        else
          result
        end
    end
  end

  # -- Memory sampling --

  defp sample_memory_loop(node, duration_ms) do
    deadline = System.monotonic_time(:millisecond) + duration_ms

    Stream.repeatedly(fn ->
      Process.sleep(1_000)
      :sample
    end)
    |> Stream.take_while(fn _ ->
      System.monotonic_time(:millisecond) < deadline
    end)
    |> Enum.each(fn _ ->
      case :rpc.call(node, :erlang, :memory, [:total]) do
        {:badrpc, _reason} -> :ok
        bytes when is_integer(bytes) -> LoadTest.Metrics.record_memory(bytes)
      end
    end)

    # Final sample
    case :rpc.call(node, :erlang, :memory, [:total]) do
      {:badrpc, _} -> :ok
      bytes when is_integer(bytes) -> LoadTest.Metrics.record_memory(bytes)
    end
  end
end
