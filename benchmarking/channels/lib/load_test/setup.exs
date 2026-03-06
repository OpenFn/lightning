# benchmarking/channels/lib/load_test/setup.exs
#
# Connect to Lightning BEAM, find/create channel, and manage telemetry
# collector deployment on the remote node.

defmodule LoadTest.Setup do
  @moduledoc false

  @telemetry_events [
    [:lightning, :channel_proxy, :request],
    [:lightning, :channel_proxy, :fetch_channel],
    [:lightning, :channel_proxy, :upstream]
  ]

  # -- Connection & channel setup --

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

  # -- Telemetry collector deployment --

  @doc """
  Deploy the Bench.TelemetryCollector onto the remote Lightning node.
  Reads the collector source, evals it on the remote node, and starts it.
  """
  def deploy_telemetry_collector!(node) do
    IO.write("Deploying telemetry collector... ")

    # __ENV__.file is .../lib/load_test/setup.exs — go up 2 to .../lib/
    lib_dir = Path.dirname(Path.dirname(__ENV__.file))
    source = File.read!(Path.join(lib_dir, "telemetry_collector.exs"))

    case :rpc.call(node, Code, :eval_string, [source]) do
      {:badrpc, reason} ->
        IO.puts(:stderr, "\nwarning: Failed to deploy telemetry collector")
        IO.puts(:stderr, "  Reason: #{inspect(reason)}")
        :error

      _ ->
        case :rpc.call(node, Bench.TelemetryCollector, :start, [
               @telemetry_events
             ]) do
          {:ok, _pid} ->
            IO.puts("ok")
            :ok

          {:badrpc, reason} ->
            IO.puts(:stderr, "\nwarning: Failed to start telemetry collector")
            IO.puts(:stderr, "  Reason: #{inspect(reason)}")
            :error
        end
    end
  end

  @doc """
  Fetch the telemetry summary from the remote node.
  Returns a map of event_key => stats, or nil on failure.
  """
  def get_telemetry_summary(node) do
    case :rpc.call(node, Bench.TelemetryCollector, :summary, []) do
      {:badrpc, _reason} -> nil
      summary when is_map(summary) -> summary
    end
  end

  @doc """
  Reset the telemetry collector on the remote node (between saturation steps).
  """
  def reset_telemetry_collector(node) do
    case :rpc.call(node, Bench.TelemetryCollector, :reset, []) do
      {:badrpc, _} -> :error
      :ok -> :ok
    end
  end

  @doc """
  Stop and clean up the telemetry collector on the remote node.
  """
  def teardown_telemetry_collector!(node) do
    IO.write("Tearing down telemetry collector... ")

    case :rpc.call(node, Bench.TelemetryCollector, :stop, []) do
      {:badrpc, _} -> IO.puts("skipped (not running)")
      _ -> IO.puts("ok")
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
