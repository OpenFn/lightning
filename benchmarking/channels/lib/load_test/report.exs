# benchmarking/channels/lib/load_test/report.exs
#
# Formats and prints metrics summary, including telemetry timing breakdown.

defmodule LoadTest.Report do
  @moduledoc false

  def print(summary, opts, command \\ nil) do
    direct? = opts[:scenario] == "direct_sink"

    scenario_label =
      if direct?, do: "#{opts[:scenario]} (baseline)", else: opts[:scenario]

    memory_section = format_memory_section(summary, direct?)

    IO.puts("""

    \u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
     Channel Load Test Results
    \u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
     Scenario:    #{scenario_label}
     Concurrency: #{opts[:concurrency]} VUs
     Duration:    #{summary.duration_s}s
     Command:     #{command}
    \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
     Requests:    #{summary.total_requests}
     Throughput:  #{summary.rps} req/s
     Errors:      #{summary.error_count} (#{summary.error_rate}%)
    #{format_status_codes(summary.status_codes)}\
    #{format_error_reasons(summary.error_reasons)}\
    \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
     Latency:
       p50:  #{format_us(summary.p50)}
       p95:  #{format_us(summary.p95)}
       p99:  #{format_us(summary.p99)}
       min:  #{format_us(summary.min)}
       max:  #{format_us(summary.max)}
    \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
    #{memory_section}\
    \u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
    """)
  end

  @doc """
  Print telemetry timing breakdown from the remote collector.
  Shows server-side timing for the channel proxy pipeline.
  """
  def print_telemetry(nil), do: :ok

  def print_telemetry(telemetry) when map_size(telemetry) == 0 do
    IO.puts("""
     Channel Proxy Timing (server-side):
       No telemetry data collected
    """)
  end

  def print_telemetry(telemetry) do
    # Display order: total request, then sub-spans
    rows = [
      {:request, "Total request", Map.get(telemetry, :request)},
      {:fetch_channel, "  DB lookup", Map.get(telemetry, :fetch_channel)},
      {:upstream, "  Upstream proxy", Map.get(telemetry, :upstream)}
    ]

    lines =
      rows
      |> Enum.filter(fn {_key, _label, stats} -> stats != nil end)
      |> Enum.map(fn {_key, label, stats} ->
        "     #{String.pad_trailing(label, 18)} " <>
          "p50=#{format_us(stats.p50)}, " <>
          "p95=#{format_us(stats.p95)}, " <>
          "p99=#{format_us(stats.p99)}, " <>
          "n=#{stats.count}"
      end)
      |> Enum.join("\n")

    IO.puts("""
    \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
     Channel Proxy Timing (server-side):
    #{lines}
    """)
  end

  def write_csv(summary, opts) do
    case opts[:csv] do
      nil ->
        :ok

      path ->
        IO.write("Writing CSV to #{path}... ")

        header =
          "scenario,concurrency,duration_s,total_requests,rps," <>
            "error_count,error_rate,p50_us,p95_us,p99_us,min_us,max_us," <>
            "memory_start_bytes,memory_end_bytes,memory_max_bytes,memory_delta_bytes\n"

        row =
          [
            opts[:scenario],
            opts[:concurrency],
            summary.duration_s,
            summary.total_requests,
            summary.rps,
            summary.error_count,
            summary.error_rate,
            summary.p50,
            summary.p95,
            summary.p99,
            summary.min,
            summary.max,
            summary.memory_start || "",
            summary.memory_end || "",
            summary.memory_max || "",
            summary.memory_delta || ""
          ]
          |> Enum.join(",")

        content =
          if File.exists?(path) do
            # Append without header if file exists
            row <> "\n"
          else
            header <> row <> "\n"
          end

        mode = if File.exists?(path), do: [:append], else: [:write]
        File.write!(path, content, mode)
        IO.puts("ok")
    end
  end

  # -- Formatting helpers --

  defp format_memory_section(_summary, true = _direct?) do
    " Memory:     n/a (direct sink baseline)"
  end

  defp format_memory_section(summary, _direct?) do
    """
     Memory (Lightning BEAM):
       start: #{format_bytes(summary.memory_start)}
       end:   #{format_bytes(summary.memory_end)}
       max:   #{format_bytes(summary.memory_max)}
       delta: #{format_bytes_delta(summary.memory_delta)}\
    """
  end

  defp format_us(0), do: "n/a"

  defp format_us(us) when us < 1_000,
    do: "#{us}us"

  defp format_us(us) when us < 1_000_000,
    do: "#{Float.round(us / 1_000, 1)}ms"

  defp format_us(us),
    do: "#{Float.round(us / 1_000_000, 2)}s"

  defp format_bytes(nil), do: "n/a"

  defp format_bytes(bytes) when bytes < 1_024,
    do: "#{bytes} B"

  defp format_bytes(bytes) when bytes < 1_048_576,
    do: "#{Float.round(bytes / 1_024, 1)} KB"

  defp format_bytes(bytes),
    do: "#{Float.round(bytes / 1_048_576, 1)} MB"

  defp format_bytes_delta(nil), do: "n/a"
  defp format_bytes_delta(0), do: "0 B"

  defp format_bytes_delta(bytes) when bytes > 0,
    do: "+#{format_bytes(bytes)}"

  defp format_bytes_delta(bytes),
    do: "-#{format_bytes(abs(bytes))}"

  defp format_status_codes(codes) when map_size(codes) == 0, do: ""

  defp format_status_codes(codes) do
    lines =
      codes
      |> Enum.sort_by(fn {code, _} -> code end)
      |> Enum.map(fn {code, count} -> "       #{code}: #{count}" end)
      |> Enum.join("\n")

    " Status codes:\n#{lines}\n"
  end

  defp format_error_reasons(reasons) when map_size(reasons) == 0, do: ""

  defp format_error_reasons(reasons) do
    lines =
      reasons
      |> Enum.sort_by(fn {_, count} -> -count end)
      |> Enum.take(5)
      |> Enum.map(fn {reason, count} -> "       #{reason}: #{count}" end)
      |> Enum.join("\n")

    " Top errors:\n#{lines}\n"
  end
end
