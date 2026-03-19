# benchmarking/channels/lib/load_test/main.exs
#
# Orchestrator — ties together Config, Metrics, Setup, Runner, and Report.

defmodule LoadTest do
  @moduledoc false

  def main(args) do
    # Capture the raw argv before parsing so we can reproduce the invocation
    command = reconstruct_command(args)

    opts = LoadTest.Config.parse(args)

    opts =
      if opts[:charts] do
        prefix = LoadTest.Report.generate_output_prefix(opts)
        Map.put(opts, :output_prefix, prefix)
      else
        opts
      end

    # Start the Finch HTTP client pool
    {:ok, _} =
      Finch.start_link(
        name: LoadTest.Finch,
        pools: %{
          default: [size: opts[:concurrency], count: 1]
        }
      )

    # Start the metrics collector
    {:ok, _} = LoadTest.Metrics.start_link()

    # Pre-flight: verify mock sink is reachable
    LoadTest.Setup.preflight_sink!(opts)

    direct? = opts[:scenario] == "direct_sink"

    # Build the target URL
    {channel_url, node} =
      if direct? do
        {"#{opts[:sink]}/test", nil}
      else
        # Connect to the Lightning BEAM
        node = LoadTest.Setup.connect!(opts)

        # Ensure test channel exists
        channel =
          LoadTest.Setup.ensure_channel!(node, opts)

        {"#{opts[:target]}/channels/#{channel.id}/test", node}
      end

    # Append query params (?response_size=N&delay=N) when configured
    channel_url = append_query_params(channel_url, opts)

    # Deploy telemetry collector (skip for direct_sink)
    telemetry_ok? =
      if not direct? and node do
        LoadTest.Setup.deploy_telemetry_collector!(node) == :ok
      else
        false
      end

    # Print test banner
    duration_label =
      if opts[:scenario] == "saturation",
        do: "#{opts[:duration]}s (per step)",
        else: "#{opts[:duration]}s"

    IO.puts("""

    Starting load test...
      URL:         #{channel_url}
      Scenario:    #{opts[:scenario]}
      Concurrency: #{opts[:concurrency]} VUs
      Duration:    #{duration_label}
      Payload:     #{opts[:payload_size]} bytes#{format_response_size(opts[:response_size])}#{format_delay(opts[:delay])}
      Telemetry:   #{if telemetry_ok?, do: "enabled", else: "disabled"}
      Command:     #{command}
    """)

    # Run the scenario
    if direct? do
      LoadTest.Runner.run_direct(opts[:scenario], channel_url, opts)
      print_standard_results(opts, command, node, telemetry_ok?)
    else
      result = LoadTest.Runner.run(opts[:scenario], channel_url, opts)

      if opts[:scenario] == "saturation" do
        LoadTest.Report.print_saturation(result, opts, command)

        # Charts need a CSV to read from; auto-create one if --charts without --csv
        opts_with_csv =
          if opts[:charts] and is_nil(opts[:csv]),
            do: Map.put(opts, :csv, opts[:output_prefix] <> ".csv"),
            else: opts

        LoadTest.Report.write_saturation_csv(result, opts_with_csv)

        if opts[:charts] do
          csv_path = opts_with_csv[:csv]
          LoadTest.Report.write_saturation_charts(csv_path)
        end

        if telemetry_ok? do
          LoadTest.Setup.teardown_telemetry_collector!(node)
        end
      else
        print_standard_results(opts, command, node, telemetry_ok?)
      end
    end
  end

  defp print_standard_results(opts, command, node, telemetry_ok?) do
    summary = LoadTest.Metrics.summary()
    LoadTest.Report.print(summary, opts, command)

    if telemetry_ok? do
      telemetry = LoadTest.Setup.get_telemetry_summary(node)
      LoadTest.Report.print_telemetry(telemetry)
      LoadTest.Setup.teardown_telemetry_collector!(node)
    end

    LoadTest.Report.write_csv(summary, opts)

    if opts[:charts] do
      timeseries = LoadTest.Metrics.latency_timeseries()
      LoadTest.Report.write_standard_charts(timeseries, opts)
    end
  end

  defp reconstruct_command(args) do
    script = "benchmarking/channels/load_test.exs"
    argv = Enum.join(args, " ")

    node_part =
      case Node.self() do
        :nonode@nohost -> ""
        node -> " --sname #{node}"
      end

    cookie_part =
      case Node.get_cookie() do
        :nocookie -> ""
        cookie -> " --cookie #{cookie}"
      end

    "elixir#{node_part}#{cookie_part} #{script} #{argv}"
    |> String.trim()
  end

  defp append_query_params(url, opts) do
    params =
      [
        if(opts[:response_size], do: "response_size=#{opts[:response_size]}"),
        if(opts[:delay], do: "delay=#{opts[:delay]}")
      ]
      |> Enum.reject(&is_nil/1)

    case params do
      [] -> url
      parts -> "#{url}?#{Enum.join(parts, "&")}"
    end
  end

  defp format_response_size(nil), do: ""
  defp format_response_size(n), do: "\n      Response:    #{n} bytes"

  defp format_delay(nil), do: ""
  defp format_delay(n), do: "\n      Delay:       #{n}ms"
end
