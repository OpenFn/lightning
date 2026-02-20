# benchmarking/channels/lib/load_test/metrics.exs
#
# Agent-based metrics collector for request latencies, status codes,
# errors, and BEAM memory samples.

defmodule LoadTest.Metrics do
  @moduledoc false

  use Agent

  def start_link do
    Agent.start_link(
      fn ->
        %{
          latencies: [],
          status_codes: %{},
          errors: 0,
          error_reasons: %{},
          memory_samples: [],
          start_time: System.monotonic_time(:microsecond)
        }
      end,
      name: __MODULE__
    )
  end

  def record_request(latency_us, status) do
    Agent.update(__MODULE__, fn state ->
      elapsed_us = System.monotonic_time(:microsecond) - state.start_time

      state
      |> Map.update!(:latencies, &[{elapsed_us, latency_us} | &1])
      |> Map.update!(:status_codes, fn codes ->
        Map.update(codes, status, 1, &(&1 + 1))
      end)
    end)
  end

  def record_error(reason) do
    key = inspect(reason)

    Agent.update(__MODULE__, fn state ->
      state
      |> Map.update!(:errors, &(&1 + 1))
      |> Map.update!(:error_reasons, fn reasons ->
        Map.update(reasons, key, 1, &(&1 + 1))
      end)
    end)
  end

  def reset do
    Agent.update(__MODULE__, fn state ->
      %{
        state
        | latencies: [],
          status_codes: %{},
          errors: 0,
          error_reasons: %{},
          start_time: System.monotonic_time(:microsecond)
      }
    end)
  end

  def record_memory(bytes) do
    timestamp = System.monotonic_time(:microsecond)

    Agent.update(__MODULE__, fn state ->
      Map.update!(state, :memory_samples, &[{timestamp, bytes} | &1])
    end)
  end

  def summary do
    Agent.get(__MODULE__, fn state ->
      now = System.monotonic_time(:microsecond)
      elapsed_us = now - state.start_time
      elapsed_s = max(elapsed_us / 1_000_000, 0.001)

      latencies = state.latencies |> Enum.map(&elem(&1, 1)) |> Enum.sort()
      total = length(latencies)

      memory_samples =
        state.memory_samples
        |> Enum.reverse()

      %{
        total_requests: total,
        rps: if(total > 0, do: Float.round(total / elapsed_s, 1), else: 0.0),
        error_count: state.errors,
        error_rate:
          if(total + state.errors > 0,
            do: Float.round(state.errors / (total + state.errors) * 100, 1),
            else: 0.0
          ),
        error_reasons: state.error_reasons,
        status_codes: state.status_codes,
        p50: percentile(latencies, 50),
        p95: percentile(latencies, 95),
        p99: percentile(latencies, 99),
        min: List.first(latencies, 0),
        max: List.last(latencies, 0),
        duration_s: Float.round(elapsed_s, 1),
        memory_start: memory_start(memory_samples),
        memory_end: memory_end(memory_samples),
        memory_max: memory_max(memory_samples),
        memory_delta: memory_delta(memory_samples)
      }
    end)
  end

  def latency_timeseries(bucket_s \\ 1.0) do
    Agent.get(__MODULE__, fn state ->
      bucket_us = round(bucket_s * 1_000_000)

      state.latencies
      |> Enum.group_by(fn {elapsed_us, _lat} -> div(elapsed_us, bucket_us) end)
      |> Enum.sort_by(fn {bucket, _} -> bucket end)
      |> Enum.map(fn {bucket, entries} ->
        lats = entries |> Enum.map(&elem(&1, 1)) |> Enum.sort()

        %{
          t: Float.round((bucket + 1) * bucket_s, 1),
          p50: percentile(lats, 50),
          p95: percentile(lats, 95),
          p99: percentile(lats, 99),
          count: length(lats)
        }
      end)
    end)
  end

  defp percentile([], _p), do: 0

  defp percentile(sorted, p) do
    k = max(round(length(sorted) * p / 100) - 1, 0)
    Enum.at(sorted, k, 0)
  end

  defp memory_start([{_ts, bytes} | _]), do: bytes
  defp memory_start([]), do: nil

  defp memory_end(samples) do
    case List.last(samples) do
      {_ts, bytes} -> bytes
      nil -> nil
    end
  end

  defp memory_max(samples) do
    case samples do
      [] -> nil
      _ -> samples |> Enum.map(&elem(&1, 1)) |> Enum.max()
    end
  end

  defp memory_delta(samples) do
    with {_ts1, start_bytes} <- List.first(samples),
         {_ts2, end_bytes} <- List.last(samples) do
      end_bytes - start_bytes
    else
      _ -> nil
    end
  end
end
