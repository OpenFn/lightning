# benchmarking/channels/populate_prometheus.exs
#
# Populates Prometheus / the WIP Grafana dashboard
# (observability/channel-proxy-dashboard.json) with realistic Channels
# HTTP-proxy traffic. Independent of the existing benchmark harness:
# no telemetry collector, no metrics collection, no CSV.
#
# Usage:
#   elixir --sname populate --cookie bench \
#     benchmarking/channels/populate_prometheus.exs [options]
#
# Run with --help for full usage information.

Mix.install([:finch, :jason])

defmodule PopulatePrometheus.Config do
  @moduledoc false

  @defaults %{
    target: "http://localhost:4000",
    destination: "http://localhost:4001",
    node: nil,
    cookie: nil,
    duration: 900,
    concurrency: 8,
    user: "demo@openfn.org"
  }

  @help """
  Usage: elixir --sname populate --cookie bench \\
           benchmarking/channels/populate_prometheus.exs [options]

  Options:
    --target URL         Lightning base URL (default: http://localhost:4000)
    --destination URL    Mock destination URL for channel creation (default: http://localhost:4001)
    --node NODE          Lightning node name (default: lightning@hostname)
    --cookie COOKIE      Erlang cookie (also settable via `elixir --cookie`)
    --duration SECS      Wall-clock duration in seconds (default: 900)
    --concurrency N      Worker pool size and Finch pool size (default: 8)
    --user EMAIL         Project owner email; halts if not found (default: demo@openfn.org)
    --help               Show this help
  """

  def parse(args) do
    {opts, _, invalid} =
      OptionParser.parse(args,
        strict: [
          target: :string,
          destination: :string,
          node: :string,
          cookie: :string,
          duration: :integer,
          concurrency: :integer,
          user: :string,
          help: :boolean
        ]
      )

    cond do
      opts[:help] ->
        IO.puts(@help)
        System.halt(0)

      invalid != [] ->
        IO.puts(:stderr, "error: unknown options: #{inspect(invalid)}\n")
        IO.puts(:stderr, @help)
        System.halt(1)

      true ->
        @defaults
        |> Map.merge(Map.new(opts))
        |> Map.update!(:target, &String.trim_trailing(&1, "/"))
        |> Map.update!(:destination, &String.trim_trailing(&1, "/"))
        |> apply_node_default()
        |> validate!()
    end
  end

  defp apply_node_default(%{node: nil} = config) do
    {:ok, hostname} = :inet.gethostname()
    %{config | node: "lightning@#{hostname}"}
  end

  defp apply_node_default(config), do: config

  defp validate!(config) do
    unless Node.alive?() do
      IO.puts(
        :stderr,
        "error: must be run as a named Erlang node (--sname populate --cookie bench)"
      )

      System.halt(1)
    end

    config
  end
end

defmodule PopulatePrometheus.Setup do
  @moduledoc false

  @projects ["channels-demo-a", "channels-demo-b"]
  # Each tuple: {project_name, [{channel_name, weight}, ...]}. Weight is
  # used by the traffic dispatcher; one channel per project is favoured
  # 2:1 over the others to give the dashboard "Top 10" panel real shape.
  @channels [
    {"channels-demo-a", [{"orders", 2}, {"webhooks", 1}]},
    {"channels-demo-b", [{"reports", 2}, {"alerts", 1}]}
  ]

  def connect!(opts) do
    node = String.to_atom(opts[:node])
    if opts[:cookie], do: Node.set_cookie(String.to_atom(opts[:cookie]))
    IO.write("Connecting to #{node}... ")

    case Node.connect(node) do
      true ->
        IO.puts("ok")
        node

      result ->
        halt!(
          "Could not connect to #{node} (#{inspect(result)}). " <>
            "Start Lightning as: iex --sname lightning --cookie bench -S mix phx.server"
        )
    end
  end

  def ensure_user!(node, email) do
    IO.write("Looking up user #{email}... ")

    case rpc!(node, Lightning.Accounts, :get_user_by_email, [email]) do
      nil ->
        halt!(
          "User #{email} not found. " <>
            "This script does not create users — create #{email} first."
        )

      user ->
        IO.puts("ok (id: #{short_id(user.id)})")
        user
    end
  end

  def ensure_projects_and_channels!(node, user, destination_url) do
    project_map =
      Map.new(@projects, fn name ->
        {name, ensure_project!(node, name, user)}
      end)

    weighted_channels =
      Enum.flat_map(@channels, fn {project_name, channel_specs} ->
        project = Map.fetch!(project_map, project_name)

        Enum.map(channel_specs, fn {channel_name, weight} ->
          channel =
            ensure_channel!(node, project, channel_name, destination_url, user)

          {channel, project, weight}
        end)
      end)

    {Map.values(project_map), weighted_channels}
  end

  def preflight_destination!(destination_url, finch_name) do
    IO.write("Checking mock destination at #{destination_url}... ")
    request = Finch.build(:get, destination_url <> "/")

    case Finch.request(request, finch_name, receive_timeout: 5_000) do
      {:ok, %Finch.Response{status: status}} when status < 500 ->
        IO.puts("ok (status #{status})")

      {:ok, %Finch.Response{status: status}} ->
        halt!("Mock destination returned #{status}")

      {:error, reason} ->
        halt!(
          "Could not reach mock destination: #{inspect(reason)}. " <>
            "Start it: elixir benchmarking/channels/mock_destination.exs"
        )
    end
  end

  defp ensure_project!(node, name, user) do
    case rpc!(node, Lightning.Repo, :get_by, [
           Lightning.Projects.Project,
           [name: name]
         ]) do
      nil ->
        IO.write("  Creating project '#{name}'... ")
        attrs = %{name: name, project_users: [%{user_id: user.id, role: :owner}]}

        case rpc!(node, Lightning.Projects, :create_project, [attrs, false]) do
          {:ok, project} ->
            IO.puts("ok (id: #{short_id(project.id)})")
            project

          {:error, changeset} ->
            halt!("create_project #{name} failed: #{inspect(changeset.errors)}")
        end

      project ->
        IO.puts("  Reusing project '#{name}' (id: #{short_id(project.id)})")
        project
    end
  end

  defp ensure_channel!(node, project, name, destination_url, actor) do
    case rpc!(node, Lightning.Repo, :get_by, [
           Lightning.Channels.Channel,
           [project_id: project.id, name: name]
         ]) do
      nil ->
        IO.write("    Creating channel '#{name}' on '#{project.name}'... ")

        attrs = %{
          name: name,
          destination_url: destination_url,
          project_id: project.id
        }

        case rpc!(node, Lightning.Channels, :create_channel, [
               attrs,
               [actor: actor]
             ]) do
          {:ok, channel} ->
            IO.puts("ok (id: #{short_id(channel.id)})")
            channel

          {:error, changeset} ->
            halt!("create_channel #{name} failed: #{inspect(changeset.errors)}")
        end

      channel ->
        IO.puts("    Reusing channel '#{name}' (id: #{short_id(channel.id)})")
        channel
    end
  end

  defp rpc!(node, mod, fun, args) do
    case :rpc.call(node, mod, fun, args) do
      {:badrpc, reason} ->
        halt!("RPC #{mod}.#{fun}/#{length(args)} failed: #{inspect(reason)}")

      result ->
        result
    end
  end

  defp halt!(msg) do
    IO.puts(:stderr, "\nerror: #{msg}")
    System.halt(1)
  end

  defp short_id(id) when is_binary(id), do: String.slice(id, 0, 8) <> "..."
  defp short_id(id), do: inspect(id)
end

defmodule PopulatePrometheus.Traffic do
  @moduledoc false

  import Bitwise, only: [bor: 2, bsl: 2]

  @delays [50, 100, 250, 500, 800]
  # Project A gets ~60% of non-unknown traffic, B ~40%. We multiply each
  # channel's intra-project weight by the project weight to build a flat
  # cumulative table.
  @project_weights %{"channels-demo-a" => 6, "channels-demo-b" => 4}

  def run(target, weighted_channels, finch_name, duration, concurrency) do
    counter = :counters.new(2, [:atomics])
    deadline = System.monotonic_time(:millisecond) + duration * 1_000

    started_at = System.monotonic_time(:millisecond)
    pick_table = build_pick_table(weighted_channels)

    IO.puts("Driving traffic for #{duration}s with #{concurrency} workers...")

    workers =
      for _ <- 1..concurrency do
        Task.async(fn ->
          worker_loop(target, pick_table, finch_name, counter, deadline)
        end)
      end

    Task.await_many(workers, :infinity)

    requests = :counters.get(counter, 1)
    errors = :counters.get(counter, 2)
    wall = div(System.monotonic_time(:millisecond) - started_at, 1_000)
    IO.puts("requests=#{requests} errors=#{errors} wall=#{wall}s")
  end

  defp worker_loop(target, pick_table, finch_name, counter, deadline) do
    if System.monotonic_time(:millisecond) >= deadline do
      :ok
    else
      send_one(target, pick_table, finch_name, counter)
      :timer.sleep(jitter_ms())
      worker_loop(target, pick_table, finch_name, counter, deadline)
    end
  end

  defp send_one(target, pick_table, finch_name, counter) do
    url = build_url(target, pick_table)
    request = Finch.build(:get, url)
    :counters.add(counter, 1, 1)

    case Finch.request(request, finch_name, receive_timeout: 10_000) do
      {:ok, _resp} -> :ok
      {:error, _reason} -> :counters.add(counter, 2, 1)
    end
  end

  defp build_url(target, pick_table) do
    case :rand.uniform(100) do
      n when n <= 70 ->
        "#{target}/channels/#{pick_channel_id(pick_table)}/echo"

      n when n <= 85 ->
        delay = Enum.random(@delays)
        "#{target}/channels/#{pick_channel_id(pick_table)}/echo?delay=#{delay}"

      n when n <= 95 ->
        "#{target}/channels/#{random_uuid()}/echo"

      _ ->
        "#{target}/channels/#{pick_channel_id(pick_table)}/echo?status=503"
    end
  end

  defp build_pick_table(weighted_channels) do
    {entries, total} =
      Enum.flat_map_reduce(weighted_channels, 0, fn {channel, project,
                                                     intra_weight},
                                                    acc ->
        weight = intra_weight * Map.fetch!(@project_weights, project.name)
        new_acc = acc + weight
        {[{new_acc, channel.id}], new_acc}
      end)

    {entries, total}
  end

  defp pick_channel_id({entries, total}) do
    draw = :rand.uniform(total)

    {_threshold, id} =
      Enum.find(entries, fn {threshold, _id} -> draw <= threshold end)

    id
  end

  # ~5-minute period sine wave between ~5 and ~25 req/s.
  # Sleep per-worker = (concurrency * 1000) / rps, clamped to [40, 200] ms.
  defp jitter_ms do
    secs = System.monotonic_time(:millisecond) / 1_000.0
    phase = 2.0 * :math.pi() * secs / 300.0
    rps = 15.0 + 10.0 * :math.sin(phase)
    base = trunc(8 * 1_000 / max(rps, 1.0))
    base |> max(40) |> min(200)
  end

  # Hand-built UUIDv4 from 16 random bytes (no need to pull Ecto).
  defp random_uuid do
    <<a::32, b::16, _::4, c::12, _::2, d::14, e::48>> =
      :crypto.strong_rand_bytes(16)

    # Set version (4) and variant (10xx) bits per RFC 4122.
    variant = bor(bsl(0b10, 14), d)

    :io_lib.format("~8.16.0b-~4.16.0b-4~3.16.0b-~4.16.0b-~12.16.0b", [
      a,
      b,
      c,
      variant,
      e
    ])
    |> IO.iodata_to_binary()
  end
end

defmodule PopulatePrometheus do
  @moduledoc false

  @finch_name PopulatePrometheus.Finch

  def main(args) do
    config = PopulatePrometheus.Config.parse(args)

    {:ok, _} =
      Finch.start_link(
        name: @finch_name,
        pools: %{:default => [size: config.concurrency, count: 1]}
      )

    node = PopulatePrometheus.Setup.connect!(config)
    user = PopulatePrometheus.Setup.ensure_user!(node, config.user)

    {_projects, weighted_channels} =
      PopulatePrometheus.Setup.ensure_projects_and_channels!(
        node,
        user,
        config.destination
      )

    PopulatePrometheus.Setup.preflight_destination!(
      config.destination,
      @finch_name
    )

    PopulatePrometheus.Traffic.run(
      config.target,
      weighted_channels,
      @finch_name,
      config.duration,
      config.concurrency
    )
  end
end

PopulatePrometheus.main(System.argv())
