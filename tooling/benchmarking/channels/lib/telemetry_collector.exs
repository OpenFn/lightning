# benchmarking/channels/lib/telemetry_collector.exs
#
# A lightweight telemetry collector designed to be deployed onto a remote
# Lightning BEAM node via :rpc.call(node, Code, :eval_string, [source]).
#
# Uses ETS with :public access and write_concurrency so telemetry handlers
# (running in connection processes) can write directly without going through
# the GenServer. The GenServer owns the table lifetime and handles cleanup.
#
# Usage (from load test):
#   source = File.read!("lib/telemetry_collector.exs")
#   :rpc.call(node, Code, :eval_string, [source])
#   :rpc.call(node, Bench.TelemetryCollector, :start, [events])
#   ...run test...
#   :rpc.call(node, Bench.TelemetryCollector, :summary, [])
#   :rpc.call(node, Bench.TelemetryCollector, :stop, [])

defmodule Bench.TelemetryCollector do
  use GenServer

  @table :bench_telemetry
  @handler_id "bench_telemetry_collector"

  # -- Public API --

  @doc """
  Start the collector and attach to the :stop events for the given event
  prefixes. Idempotent — if already running, resets and re-attaches.
  """
  def start(events) do
    case GenServer.start(__MODULE__, events, name: __MODULE__) do
      {:ok, pid} ->
        {:ok, pid}

      {:error, {:already_started, pid}} ->
        reset()
        {:ok, pid}
    end
  end

  @doc """
  Stop the collector, detach handlers, and delete the ETS table.
  """
  def stop do
    GenServer.stop(__MODULE__, :normal)
  catch
    :exit, _ -> :ok
  end

  @doc """
  Clear all collected data (between scenarios).
  """
  def reset do
    if :ets.info(@table) != :undefined do
      :ets.delete_all_objects(@table)
    end

    :ok
  end

  @doc """
  Aggregate collected data into a summary map. Each event gets:
  count, min, max, mean, p50, p95, p99 (all in microseconds).
  """
  def summary do
    if :ets.info(@table) == :undefined do
      %{}
    else
      @table
      |> :ets.tab2list()
      |> Enum.group_by(&elem(&1, 0), &elem(&1, 1))
      |> Enum.into(%{}, fn {event_key, durations} ->
        sorted = Enum.sort(durations)
        count = length(sorted)

        stats = %{
          count: count,
          min: List.first(sorted, 0),
          max: List.last(sorted, 0),
          mean:
            if(count > 0,
              do: Float.round(Enum.sum(sorted) / count, 1),
              else: 0.0
            ),
          p50: percentile(sorted, 50),
          p95: percentile(sorted, 95),
          p99: percentile(sorted, 99)
        }

        {event_key, stats}
      end)
    end
  end

  # -- GenServer callbacks --

  @impl true
  def init(events) do
    # Create ETS table: :duplicate_bag allows multiple entries per key
    # (including identical {key, value} pairs — :bag would deduplicate those),
    # :public lets handler processes write directly,
    # write_concurrency optimizes for concurrent inserts.
    table =
      :ets.new(@table, [
        :duplicate_bag,
        :named_table,
        :public,
        write_concurrency: true
      ])

    # Attach to :stop events for each prefix
    stop_events = Enum.map(events, &(&1 ++ [:stop]))

    :telemetry.attach_many(
      @handler_id,
      stop_events,
      &__MODULE__.handle_event/4,
      nil
    )

    {:ok, %{table: table}}
  end

  @impl true
  def terminate(_reason, _state) do
    :telemetry.detach(@handler_id)

    if :ets.info(@table) != :undefined do
      :ets.delete(@table)
    end

    :ok
  catch
    _, _ -> :ok
  end

  # -- Telemetry handler (runs in the calling process, not GenServer) --

  def handle_event(event, %{duration: duration}, _metadata, _config) do
    # event is e.g. [:lightning, :channel_proxy, :request, :stop]
    # Convert to a key like :request, :fetch_channel, :upstream
    event_key = event |> Enum.at(-2)

    # duration is in native units, convert to microseconds
    duration_us = System.convert_time_unit(duration, :native, :microsecond)

    if :ets.info(@table) != :undefined do
      :ets.insert(@table, {event_key, duration_us})
    end
  end

  def handle_event(_event, _measurements, _metadata, _config), do: :ok

  # -- Private helpers --

  defp percentile([], _p), do: 0

  defp percentile(sorted, p) do
    k = max(round(length(sorted) * p / 100) - 1, 0)
    Enum.at(sorted, k, 0)
  end
end
