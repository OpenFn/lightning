# benchmarking/channels/lib/load_test/config.exs
#
# CLI argument parsing and validation for the channel load test.

defmodule LoadTest.Config do
  @moduledoc false

  @scenarios ~w(happy_path ramp_up saturation large_payload large_response mixed_methods slow_sink direct_sink)

  @defaults %{
    target: "http://localhost:4000",
    sink: "http://localhost:4001",
    node: nil,
    cookie: nil,
    channel: "load-test",
    scenario: "happy_path",
    concurrency: 10,
    duration: 30,
    payload_size: 1024,
    response_size: nil,
    delay: nil,
    csv: nil,
    charts: false
  }

  @help """
  Usage: elixir --sname loadtest --cookie COOKIE \\
           benchmarking/channels/load_test.exs [options]

  Options:
    --target URL         Lightning base URL (default: http://localhost:4000)
    --sink URL           Mock sink URL for channel creation (default: http://localhost:4001)
    --node NODE          Lightning node name (default: lightning@hostname)
    --cookie COOKIE      Erlang cookie (can also use --cookie flag on elixir command)
    --channel NAME       Channel name to find/create (default: load-test)
    --scenario SCENARIO  Test scenario (default: happy_path)
    --concurrency N      Concurrent virtual users (default: 10)
    --duration SECS      Test duration in seconds (default: 30)
    --payload-size BYTES  Request body size (default: 1024)
    --response-size BYTES Response body size override via query param (default: none)
    --delay MS            Sink response delay via query param (default: none; slow_sink: 2000)
    --csv PATH            Optional CSV output file for results
    --charts              Generate gnuplot charts (PNG files in /tmp or next to --csv)
    --help                Show this help

  Scenarios:
    happy_path      Sustained POST requests at --concurrency VUs for --duration seconds
    ramp_up         Ramp from 1 to --concurrency VUs over --duration seconds
    saturation      Ramp through concurrency levels, report per-step (find throughput ceiling)
    large_payload   POST with --payload-size bodies (default 1MB), check memory stays flat
    large_response  GET requests; mock sink returns large bodies. Reports memory
    mixed_methods   Rotate through GET, POST, PUT, PATCH, DELETE
    slow_sink       Sink with --delay ms (default 2000); measures TTFB and latency
    direct_sink     Hit mock sink directly (no Lightning), baseline measurement

  Note: Most scenarios require a named node (--sname) to connect to Lightning.
  The direct_sink scenario does not require --sname or a running Lightning instance.
  The --cookie flag on the elixir command sets the Erlang cookie. The
  script also accepts --cookie in its own args as a convenience.
  """

  def parse(args) do
    case parse_args(args, @defaults) do
      :help ->
        IO.puts(@help)
        System.halt(0)

      {:error, message} ->
        IO.puts(:stderr, "error: #{message}\n")
        IO.puts(:stderr, @help)
        System.halt(1)

      config ->
        config
        |> apply_defaults()
        |> validate!()
    end
  end

  defp parse_args([], acc), do: acc
  defp parse_args(["--help" | _], _acc), do: :help

  defp parse_args(["--target", value | rest], acc),
    do: parse_args(rest, %{acc | target: String.trim_trailing(value, "/")})

  defp parse_args(["--sink", value | rest], acc),
    do: parse_args(rest, %{acc | sink: String.trim_trailing(value, "/")})

  defp parse_args(["--node", value | rest], acc),
    do: parse_args(rest, %{acc | node: value})

  defp parse_args(["--cookie", value | rest], acc),
    do: parse_args(rest, %{acc | cookie: value})

  defp parse_args(["--channel", value | rest], acc),
    do: parse_args(rest, %{acc | channel: value})

  defp parse_args(["--scenario", value | rest], acc) do
    if value in @scenarios do
      parse_args(rest, %{acc | scenario: value})
    else
      {:error,
       "unknown scenario: #{value}. Expected one of: #{Enum.join(@scenarios, ", ")}"}
    end
  end

  defp parse_args(["--concurrency", value | rest], acc) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> parse_args(rest, %{acc | concurrency: n})
      _ -> {:error, "invalid concurrency: #{value}"}
    end
  end

  defp parse_args(["--duration", value | rest], acc) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> parse_args(rest, %{acc | duration: n})
      _ -> {:error, "invalid duration: #{value}"}
    end
  end

  defp parse_args(["--payload-size", value | rest], acc) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> parse_args(rest, %{acc | payload_size: n})
      _ -> {:error, "invalid payload-size: #{value}"}
    end
  end

  defp parse_args(["--response-size", value | rest], acc) do
    case Integer.parse(value) do
      {n, ""} when n > 0 -> parse_args(rest, %{acc | response_size: n})
      _ -> {:error, "invalid response-size: #{value}"}
    end
  end

  defp parse_args(["--delay", value | rest], acc) do
    case Integer.parse(value) do
      {n, ""} when n >= 0 -> parse_args(rest, %{acc | delay: n})
      _ -> {:error, "invalid delay: #{value}"}
    end
  end

  defp parse_args(["--csv", value | rest], acc),
    do: parse_args(rest, %{acc | csv: value})

  defp parse_args(["--charts" | rest], acc),
    do: parse_args(rest, %{acc | charts: true})

  defp parse_args([unknown | _], _acc),
    do: {:error, "unknown option: #{unknown}"}

  defp apply_defaults(%{node: nil} = config) do
    {:ok, hostname} = :inet.gethostname()
    %{config | node: "lightning@#{hostname}"}
  end

  defp apply_defaults(config), do: config

  defp apply_defaults_for_scenario(
         %{scenario: "large_payload", payload_size: 1024} = config
       ) do
    %{config | payload_size: 1_048_576}
  end

  defp apply_defaults_for_scenario(
         %{scenario: "large_response", response_size: nil} = config
       ) do
    %{config | response_size: 1_048_576}
  end

  defp apply_defaults_for_scenario(%{scenario: "slow_sink", delay: nil} = config) do
    %{config | delay: 2_000}
  end

  defp apply_defaults_for_scenario(config), do: config

  defp validate!(config) do
    config = apply_defaults_for_scenario(config)

    if config.scenario == "direct_sink" or Node.alive?() do
      config
    else
      IO.puts(:stderr, """
      error: This script must be run as a named Erlang node.

      Use: elixir --sname loadtest --cookie COOKIE benchmarking/channels/load_test.exs
      """)

      System.halt(1)
    end
  end
end
