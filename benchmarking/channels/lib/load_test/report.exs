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

  # -- Saturation output --

  def print_saturation(results, opts, command \\ nil) do
    header = """

    \u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
     Saturation Test Results
    \u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550
     Max VUs:     #{opts[:concurrency]}
     Per-step:    #{opts[:duration]}s
     Steps:       #{length(results)}
     Command:     #{command}
    \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
    """

    table_header =
      "  #{pad_r("VUs", 6)} #{pad_r("RPS", 9)} #{pad_r("Reqs", 8)} " <>
        "#{pad_r("Errors", 8)} #{pad_r("p50", 10)} #{pad_r("p95", 10)} #{pad_r("p99", 10)}"

    separator =
      "  #{String.duplicate("\u2500", 5)} " <>
        "#{String.duplicate("\u2500", 8)} " <>
        "#{String.duplicate("\u2500", 7)} " <>
        "#{String.duplicate("\u2500", 7)} " <>
        "#{String.duplicate("\u2500", 9)} " <>
        "#{String.duplicate("\u2500", 9)} " <>
        "#{String.duplicate("\u2500", 9)}"

    rows =
      results
      |> Enum.map(fn %{concurrency: c, summary: s} ->
        "  #{pad_r(to_string(c), 6)} " <>
          "#{pad_r(to_string(s.rps), 9)} " <>
          "#{pad_r(to_string(s.total_requests), 8)} " <>
          "#{pad_r(to_string(s.error_count), 8)} " <>
          "#{pad_r(format_us(s.p50), 10)} " <>
          "#{pad_r(format_us(s.p95), 10)} " <>
          "#{pad_r(format_us(s.p99), 10)}"
      end)
      |> Enum.join("\n")

    footer =
      "\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550\u2550"

    IO.puts(header)
    IO.puts(table_header)
    IO.puts(separator)
    IO.puts(rows)
    IO.puts("    #{footer}")

    # Print server-side telemetry table if any step has it
    if Enum.any?(results, fn %{telemetry: t} -> t != nil and map_size(t) > 0 end) do
      print_saturation_telemetry(results)
    end
  end

  defp print_saturation_telemetry(results) do
    IO.puts("""

    \u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500\u2500
     Server-side Timing (per step):
    """)

    for %{concurrency: c, telemetry: t} <- results, t != nil, map_size(t) > 0 do
      request = Map.get(t, :request)
      db = Map.get(t, :fetch_channel)
      upstream = Map.get(t, :upstream)

      parts =
        [
          if(request,
            do: "req p50=#{format_us(request.p50)}/p95=#{format_us(request.p95)}"
          ),
          if(db, do: "db p50=#{format_us(db.p50)}"),
          if(upstream, do: "up p50=#{format_us(upstream.p50)}")
        ]
        |> Enum.reject(&is_nil/1)
        |> Enum.join(", ")

      IO.puts("    #{pad_r("#{c} VUs:", 10)} #{parts}")
    end
  end

  def write_saturation_csv(results, opts) do
    case opts[:csv] do
      nil ->
        :ok

      path ->
        IO.write("Writing saturation CSV to #{path}... ")

        header =
          "step,concurrency,duration_s,requests,rps,errors,error_rate," <>
            "p50_us,p95_us,p99_us,min_us,max_us,memory_end_bytes," <>
            "server_request_p50_us,server_request_p95_us," <>
            "server_db_p50_us,server_upstream_p50_us\n"

        rows =
          results
          |> Enum.with_index(1)
          |> Enum.map(fn {%{concurrency: c, summary: s, telemetry: t}, step} ->
            tel_request = if t, do: Map.get(t, :request)
            tel_db = if t, do: Map.get(t, :fetch_channel)
            tel_upstream = if t, do: Map.get(t, :upstream)

            [
              step,
              c,
              s.duration_s,
              s.total_requests,
              s.rps,
              s.error_count,
              s.error_rate,
              s.p50,
              s.p95,
              s.p99,
              s.min,
              s.max,
              s.memory_end || "",
              if(tel_request, do: tel_request.p50, else: ""),
              if(tel_request, do: tel_request.p95, else: ""),
              if(tel_db, do: tel_db.p50, else: ""),
              if(tel_upstream, do: tel_upstream.p50, else: "")
            ]
            |> Enum.join(",")
          end)
          |> Enum.join("\n")

        content =
          if File.exists?(path) do
            rows <> "\n"
          else
            header <> rows <> "\n"
          end

        mode = if File.exists?(path), do: [:append], else: [:write]
        File.write!(path, content, mode)
        IO.puts("ok")
    end
  end

  def write_saturation_charts(csv_path) do
    basename = Path.rootname(csv_path)
    script_path = basename <> ".gnuplot"
    throughput_png = basename <> "_throughput.png"
    latency_png = basename <> "_latency.png"

    # Build latency plot with gnuplot line continuations.
    # Can't use \\ at end-of-line in heredocs (Elixir treats \ as continuation),
    # so we concatenate the pieces explicitly.
    latency_plot =
      "plot '#{csv_path}' every ::1 using 2:($8/1000) with linespoints pt 7 lw 2 title 'p50', \\\n" <>
        "     ''             every ::1 using 2:($9/1000) with linespoints pt 5 lw 2 title 'p95', \\\n" <>
        "     ''             every ::1 using 2:($10/1000) with linespoints pt 9 lw 2 title 'p99'\n"

    script =
      """
      set datafile separator ','
      set terminal pngcairo size 1024,600 enhanced font 'sans,11'
      set grid
      set xlabel 'Concurrency (VUs)'

      # Chart 1: Throughput
      set output '#{throughput_png}'
      set title 'Saturation: Throughput vs Concurrency'
      set ylabel 'Throughput (req/s)'
      plot '#{csv_path}' every ::1 using 2:5 with linespoints pt 7 ps 1.2 lw 2 title 'RPS'

      # Chart 2: Latency
      set output '#{latency_png}'
      set title 'Saturation: Latency vs Concurrency'
      set ylabel 'Latency (ms)'
      set key top left
      """ <> latency_plot

    File.write!(script_path, script)

    run_gnuplot(script_path, [throughput_png, latency_png])
  end

  def write_standard_charts(timeseries, opts) do
    prefix =
      if opts[:output_prefix] do
        opts[:output_prefix]
      else
        Path.rootname(opts[:csv])
      end

    script_path = prefix <> "_latency.gnuplot"
    latency_png = prefix <> "_latency.png"

    # columns: t p50_ms p95_ms p99_ms rps
    data_lines =
      timeseries
      |> Enum.map(fn %{t: t, p50: p50, p95: p95, p99: p99, count: count} ->
        p50_ms = Float.round(p50 / 1_000, 2)
        p95_ms = Float.round(p95 / 1_000, 2)
        p99_ms = Float.round(p99 / 1_000, 2)
        "#{t} #{p50_ms} #{p95_ms} #{p99_ms} #{count}"
      end)
      |> Enum.join("\n")

    title =
      "#{opts[:scenario]}: Throughput & Latency (#{opts[:concurrency]} VUs)"

    # Build plot command with gnuplot line continuations.
    # Can't use \\ at end-of-line in heredocs (Elixir treats \ as continuation),
    # so we concatenate explicitly.
    # RPS as filled area on y2 (background), latency lines on y1 (foreground).
    plot_cmd =
      "plot $DATA using 1:5 axes x1y2 with filledcurves x1 fs transparent solid 0.15 lc rgb '#999999' title 'RPS', \\\n" <>
        "     ''    using 1:2 axes x1y1 with linespoints pt 7 lw 2 title 'p50', \\\n" <>
        "     ''    using 1:3 axes x1y1 with linespoints pt 5 lw 2 title 'p95', \\\n" <>
        "     ''    using 1:4 axes x1y1 with linespoints pt 9 lw 2 title 'p99'\n"

    script =
      """
      $DATA << EOD
      #{data_lines}
      EOD

      set terminal pngcairo size 1024,600 enhanced font 'sans,11'
      set output '#{latency_png}'
      set title '#{title}'
      set xlabel 'Time (s)'
      set ylabel 'Latency (ms)'
      set y2label 'Throughput (req/s)'
      set y2tics
      set ytics nomirror
      set grid
      set key top left
      """ <> plot_cmd

    File.write!(script_path, script)

    run_gnuplot(script_path, [latency_png])
  end

  def generate_output_prefix(opts) do
    timestamp = Calendar.strftime(DateTime.utc_now(), "%Y%m%d_%H%M%S")
    "/tmp/loadtest_#{opts[:scenario]}_#{timestamp}"
  end

  defp run_gnuplot(script_path, png_paths) do
    case System.cmd("gnuplot", [script_path], stderr_to_stdout: true) do
      {_, 0} ->
        [first | rest] = png_paths
        IO.puts("Charts: #{first}")
        Enum.each(rest, fn path -> IO.puts("        #{path}") end)

      {output, _} ->
        IO.puts("gnuplot script: #{script_path}")
        IO.puts("  Run manually: gnuplot #{script_path}")

        if output =~ "not found" or output =~ "No such file" do
          IO.puts("  Install: pacman -S gnuplot (or apt install gnuplot)")
        end
    end
  rescue
    ErlangError ->
      IO.puts("gnuplot script: #{script_path}")

      IO.puts(
        "  gnuplot not found — install: pacman -S gnuplot (or apt install gnuplot)"
      )
  end

  # -- Standard CSV --

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

  defp pad_r(str, width), do: String.pad_trailing(str, width)
end
