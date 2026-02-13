# benchmarking/channels/lib/load_test/main.exs
#
# Orchestrator — ties together Config, Metrics, Setup, Runner, and Report.

defmodule LoadTest do
  @moduledoc false

  def main(args) do
    # Capture the raw argv before parsing so we can reproduce the invocation
    command = reconstruct_command(args)

    opts = LoadTest.Config.parse(args)

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
    IO.puts("""

    Starting load test...
      URL:         #{channel_url}
      Scenario:    #{opts[:scenario]}
      Concurrency: #{opts[:concurrency]} VUs
      Duration:    #{opts[:duration]}s
      Payload:     #{opts[:payload_size]} bytes#{format_response_size(opts[:response_size])}#{format_delay(opts[:delay])}
      Telemetry:   #{if telemetry_ok?, do: "enabled", else: "disabled"}
      Command:     #{command}
    """)

    # Run the scenario
    if direct? do
      LoadTest.Runner.run_direct(opts[:scenario], channel_url, opts)
    else
      LoadTest.Runner.run(opts[:scenario], channel_url, opts)
    end

    # Collect and print results
    summary = LoadTest.Metrics.summary()
    LoadTest.Report.print(summary, opts, command)

    # Print telemetry breakdown if available
    if telemetry_ok? do
      telemetry = LoadTest.Setup.get_telemetry_summary(node)
      LoadTest.Report.print_telemetry(telemetry)
      LoadTest.Setup.teardown_telemetry_collector!(node)
    end

    LoadTest.Report.write_csv(summary, opts)
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
