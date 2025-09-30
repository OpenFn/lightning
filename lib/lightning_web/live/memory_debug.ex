defmodule LightningWeb.Live.MemoryDebug do
  @moduledoc """
  Memory debugging utilities for LiveViews to track memory usage and help
  diagnose OOM issues.

  Usage in a LiveView:

      import LightningWeb.Live.MemoryDebug

      def mount(params, session, socket) do
        log_memory("mount start")

        # ... your code ...

        socket = assign(socket, :data, large_data)
        log_memory("after loading large data", socket: socket)

        {:ok, socket}
      end
  """

  require Logger

  @doc """
  Logs current memory usage for the calling process and optionally the socket assigns.

  ## Options

    * `:socket` - Phoenix.LiveView.Socket to measure assigns memory
    * `:assigns` - List of assign keys to measure individually (e.g., [:dataclip, :workflow])
  """
  def log_memory(label, opts \\ []) do
    pid = self()

    case Process.info(pid, [:memory, :message_queue_len]) do
      [{:memory, memory}, {:message_queue_len, queue_len}] ->
        memory_mb = Float.round(memory / 1_048_576, 2)

        base_msg = "MEMORY [#{label}] Process: #{memory_mb}MB, Queue: #{queue_len}"

        extra_info =
          case Keyword.get(opts, :socket) do
            nil ->
              ""
            socket ->
              assigns_info = measure_assigns(socket, Keyword.get(opts, :assigns, []))
              ", #{assigns_info}"
          end

        Logger.info(base_msg <> extra_info)

        # Also log system-wide memory if this is a significant spike
        if memory_mb > 50 do
          total_mb = Float.round(:erlang.memory(:total) / 1_048_576, 2)
          processes_mb = Float.round(:erlang.memory(:processes) / 1_048_576, 2)
          Logger.warning("MEMORY [#{label}] ⚠️  HIGH USAGE - System total: #{total_mb}MB, Processes: #{processes_mb}MB")
        end

      nil ->
        Logger.debug("MEMORY [#{label}] Process info not available")
    end

    :ok
  end

  @doc """
  Wraps a function call with before/after memory logging.

  ## Examples

      measure("load dataclip", fn ->
        Invocation.get_dataclip!(id)
      end)
  """
  def measure(label, fun) when is_function(fun, 0) do
    log_memory("#{label} - before")
    result = fun.()
    log_memory("#{label} - after")
    result
  end

  @doc """
  Measures memory of specific socket assigns.
  """
  def measure_assigns(%Phoenix.LiveView.Socket{assigns: assigns}, keys) when is_list(keys) do
    measurements =
      for key <- keys, Map.has_key?(assigns, key) do
        value = Map.get(assigns, key)
        size = :erts_debug.size(value) * :erlang.system_info(:wordsize)
        size_mb = Float.round(size / 1_048_576, 2)
        "#{key}: #{size_mb}MB"
      end

    if Enum.empty?(measurements) do
      "No assigns to measure"
    else
      "Assigns(" <> Enum.join(measurements, ", ") <> ")"
    end
  end

  def measure_assigns(_socket, _keys), do: ""

  @doc """
  Gets a memory snapshot as a map (useful for comparing before/after).
  """
  def snapshot do
    case Process.info(self(), [:memory, :message_queue_len]) do
      [{:memory, memory}, {:message_queue_len, queue_len}] ->
        %{
          process_memory_bytes: memory,
          process_memory_mb: Float.round(memory / 1_048_576, 2),
          message_queue_len: queue_len,
          system_total_mb: Float.round(:erlang.memory(:total) / 1_048_576, 2),
          processes_mb: Float.round(:erlang.memory(:processes) / 1_048_576, 2)
        }
      nil ->
        %{error: :process_info_unavailable}
    end
  end

  @doc """
  Compares two memory snapshots and logs the difference.
  """
  def compare_snapshots(before, after_snap, label) do
    if is_map(before) and is_map(after_snap) do
      diff_mb = after_snap.process_memory_mb - before.process_memory_mb
      system_diff = after_snap.system_total_mb - before.system_total_mb

      Logger.info(
        "MEMORY [#{label}] Change: #{format_diff(diff_mb)}MB process, " <>
        "#{format_diff(system_diff)}MB system total"
      )
    end
  end

  defp format_diff(num) when num > 0, do: "+#{num}"
  defp format_diff(num), do: "#{num}"
end
