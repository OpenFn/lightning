# benchmarking/channels/load_test.exs
#
# A standalone load test script that drives HTTP traffic through a running
# Lightning instance's channel proxy to a mock sink, collects latency and
# memory metrics, and reports results.
#
# Requires a named Erlang node so it can connect to the Lightning BEAM
# for channel setup and memory sampling.
#
# Usage:
#   elixir --sname loadtest --cookie SECRET \
#     benchmarking/channels/load_test.exs [options]
#
# Examples:
#   # Happy path with defaults (10 VUs, 30s)
#   elixir --sname loadtest --cookie SECRET \
#     benchmarking/channels/load_test.exs
#
#   # Ramp up to 50 concurrent users over 60 seconds
#   elixir --sname loadtest --cookie SECRET \
#     benchmarking/channels/load_test.exs \
#     --scenario ramp_up --concurrency 50 --duration 60
#
#   # Large payload test with CSV output
#   elixir --sname loadtest --cookie SECRET \
#     benchmarking/channels/load_test.exs \
#     --scenario large_payload --payload-size 1048576 --csv results.csv

Mix.install([:finch, :jason])

# -------------------------------------------------------------------
# LoadTest.Config — CLI argument parsing and validation
# -------------------------------------------------------------------
defmodule LoadTest.Config do
  @moduledoc false

  @scenarios ~w(happy_path ramp_up large_payload large_response mixed_methods slow_sink direct_sink)

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
    csv: nil
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
    --help                Show this help

  Scenarios:
    happy_path      Sustained POST requests at --concurrency VUs for --duration seconds
    ramp_up         Ramp from 1 to --concurrency VUs over --duration seconds
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

# -------------------------------------------------------------------
# LoadTest.Metrics — Agent-based metrics collector
# -------------------------------------------------------------------
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
      state
      |> Map.update!(:latencies, &[latency_us | &1])
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

      latencies = Enum.sort(state.latencies)
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

# -------------------------------------------------------------------
# LoadTest.Setup — Connect to Lightning BEAM, find/create channel
# -------------------------------------------------------------------
defmodule LoadTest.Setup do
  @moduledoc false

  def connect!(opts) do
    node = String.to_atom(opts[:node])

    if opts[:cookie] do
      Node.set_cookie(String.to_atom(opts[:cookie]))
    end

    IO.write("Connecting to #{node}... ")

    case Node.connect(node) do
      true ->
        IO.puts("ok")
        node

      false ->
        IO.puts(:stderr, "\nerror: Could not connect to #{node}")

        IO.puts(:stderr, """

        Make sure:
          1. Lightning is running as a named node (e.g. --sname lightning)
          2. The cookie matches (e.g. --cookie SECRET)
          3. Both nodes are on the same network/machine
        """)

        System.halt(1)

      :ignored ->
        IO.puts(
          :stderr,
          "\nerror: Node.connect returned :ignored. Is this node alive?"
        )

        System.halt(1)
    end
  end

  def ensure_channel!(node, opts) do
    channel_name = opts[:channel]
    sink_url = opts[:sink]

    IO.write("Looking up channel '#{channel_name}'... ")

    case rpc!(node, Lightning.Repo, :get_by, [
           Lightning.Channels.Channel,
           [name: channel_name]
         ]) do
      nil ->
        IO.puts("not found, creating")
        project = ensure_project!(node)
        create_channel!(node, channel_name, sink_url, project.id)

      %{enabled: false} = channel ->
        IO.puts("found (disabled), enabling")
        enable_channel!(node, channel)

      channel ->
        IO.puts("found (id: #{short_id(channel.id)})")
        channel
    end
  end

  def preflight_sink!(opts) do
    sink_url = opts[:sink]
    IO.write("Checking mock sink at #{sink_url}... ")

    request = Finch.build(:get, sink_url)

    case Finch.request(request, LoadTest.Finch, receive_timeout: 5_000) do
      {:ok, %Finch.Response{status: status}} when status < 500 ->
        IO.puts("ok (status #{status})")

      {:ok, %Finch.Response{status: status}} ->
        IO.puts(:stderr, "\nwarning: Mock sink returned #{status}")

      {:error, reason} ->
        IO.puts(:stderr, "\nerror: Could not reach mock sink at #{sink_url}")
        IO.puts(:stderr, "  Reason: #{inspect(reason)}")

        IO.puts(:stderr, """

        Start the mock sink first:
          elixir benchmarking/channels/mock_sink.exs
        """)

        System.halt(1)
    end
  end

  # -- Private helpers --

  defp ensure_project!(node) do
    case rpc!(node, Lightning.Repo, :get_by, [
           Lightning.Projects.Project,
           [name: "load-test"]
         ]) do
      nil ->
        IO.write("  Creating 'load-test' project... ")
        user = ensure_user!(node)

        case rpc!(node, Lightning.Projects, :create_project, [
               %{
                 name: "load-test",
                 project_users: [%{user_id: user.id, role: :owner}]
               },
               false
             ]) do
          {:ok, project} ->
            IO.puts("ok (id: #{short_id(project.id)})")
            project

          {:error, changeset} ->
            IO.puts(:stderr, "\nerror: Failed to create project")
            IO.puts(:stderr, "  #{inspect(changeset.errors)}")
            System.halt(1)
        end

      project ->
        IO.puts(
          "  Using existing 'load-test' project (id: #{short_id(project.id)})"
        )

        project
    end
  end

  defp ensure_user!(node) do
    email = "load-test@openfn.org"

    case rpc!(node, Lightning.Repo, :get_by, [
           Lightning.Accounts.User,
           [email: email]
         ]) do
      nil ->
        IO.write("  Creating load-test user... ")

        {:ok, user} =
          rpc!(node, Lightning.Accounts, :register_user, [
            %{
              first_name: "Load",
              last_name: "Test",
              email: email,
              password: "load-test-password-12345"
            }
          ])

        IO.puts("ok")
        user

      user ->
        user
    end
  end

  defp create_channel!(node, name, sink_url, project_id) do
    IO.write("  Creating channel '#{name}'... ")

    case rpc!(node, Lightning.Channels, :create_channel, [
           %{name: name, sink_url: sink_url, project_id: project_id}
         ]) do
      {:ok, channel} ->
        IO.puts("ok (id: #{short_id(channel.id)})")
        channel

      {:error, changeset} ->
        IO.puts(:stderr, "\nerror: Failed to create channel")
        IO.puts(:stderr, "  #{inspect(changeset.errors)}")
        System.halt(1)
    end
  end

  defp enable_channel!(node, channel) do
    case rpc!(node, Lightning.Channels, :update_channel, [
           channel,
           %{enabled: true}
         ]) do
      {:ok, channel} ->
        IO.puts("  Enabled channel (id: #{short_id(channel.id)})")
        channel

      {:error, changeset} ->
        IO.puts(:stderr, "\nerror: Failed to enable channel")
        IO.puts(:stderr, "  #{inspect(changeset.errors)}")
        System.halt(1)
    end
  end

  defp rpc!(node, mod, fun, args) do
    case :rpc.call(node, mod, fun, args) do
      {:badrpc, reason} ->
        IO.puts(
          :stderr,
          "\nerror: RPC call failed: #{mod}.#{fun}/#{length(args)}"
        )

        IO.puts(:stderr, "  Reason: #{inspect(reason)}")
        System.halt(1)

      result ->
        result
    end
  end

  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8) <> "..."
  defp short_id(id), do: inspect(id)
end

# -------------------------------------------------------------------
# LoadTest.Runner — Executes test scenarios
# -------------------------------------------------------------------
defmodule LoadTest.Runner do
  @moduledoc false

  @methods [:get, :post, :put, :patch, :delete]

  def run(scenario, channel_url, opts) do
    duration_ms = opts[:duration] * 1_000
    node = String.to_atom(opts[:node])

    # Start memory sampler in background
    memory_task =
      Task.async(fn -> sample_memory_loop(node, duration_ms) end)

    # Run the appropriate scenario
    case scenario do
      "ramp_up" -> run_ramp_up(channel_url, opts, duration_ms)
      _ -> run_steady(scenario, channel_url, opts, duration_ms)
    end

    Task.await(memory_task, :infinity)
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

# -------------------------------------------------------------------
# LoadTest.Report — Formats and prints metrics summary
# -------------------------------------------------------------------
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

# -------------------------------------------------------------------
# LoadTest — Main entry point
# -------------------------------------------------------------------
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
    channel_url =
      if direct? do
        "#{opts[:sink]}/test"
      else
        # Connect to the Lightning BEAM
        LoadTest.Setup.connect!(opts)

        # Ensure test channel exists
        channel =
          LoadTest.Setup.ensure_channel!(String.to_atom(opts[:node]), opts)

        "#{opts[:target]}/channels/#{channel.id}/test"
      end

    # Append query params (?response_size=N&delay=N) when configured
    channel_url = append_query_params(channel_url, opts)

    # Print test banner
    IO.puts("""

    Starting load test...
      URL:         #{channel_url}
      Scenario:    #{opts[:scenario]}
      Concurrency: #{opts[:concurrency]} VUs
      Duration:    #{opts[:duration]}s
      Payload:     #{opts[:payload_size]} bytes#{format_response_size(opts[:response_size])}#{format_delay(opts[:delay])}
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

LoadTest.main(System.argv())
