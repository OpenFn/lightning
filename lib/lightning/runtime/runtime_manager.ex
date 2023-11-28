defmodule Lightning.Runtime.RuntimeManager do
  # https://registry.npmjs.org/lightning-runtime/latest
  @latest_version "0.1.0"

  @moduledoc """
  Locates and runs the Runtime server. Added in order to ease development and default installations of Lightning

  ## Runtime configuration

  Sample:

    config :lightining, #{__MODULE__},
      version: "#{@latest_version}",
      start: true,
      args: ~w(js/app.js --bundle --target=es2016 --outdir=../priv/static/assets),
      cd: Path.expand("../assets", __DIR__),
      env: %{}

  Options:

    * `:version` - the expected runtime version

    * `:start` - flag to start the runtime manager. If `false` the GenServer
       won't be started

    * `:path` - the path to find the runtime executable at. By
      default, it is automatically downloaded and placed inside
      the `_build` directory of your current app

  Overriding the `:path` is not recommended, as we will automatically
  download and manage the `runtime` for you.


  """
  defmodule Config do
    @moduledoc false

    defstruct backoff: [min: 0.5, max: 5],
              env: [],
              ws_url: "ws://localhost:4000/worker",
              cmd: ~w(node ./node_modules/.bin/worker),
              cd: Path.expand("../../../assets", __DIR__),
              worker_secret: nil,
              capacity: 5,
              repo_dir: nil

    @doc """
    Parses the keyword list of start arguments and returns a tuple,
    the first element being the config struct and the second element
    being the remaining arguments.
    """
    def parse(args) do
      config =
        struct(
          __MODULE__,
          Application.get_env(:lightning, __MODULE__, [])
          |> Keyword.merge(args)
        )

      {_, args} = args |> Keyword.split(config |> Map.keys())

      {config, args}
    end

    def to_args(config) do
      config.cmd
      |> Enum.concat(
        config
        |> Map.from_struct()
        |> Enum.flat_map(&to_arg/1)
        |> Enum.reject(&is_nil/1)
      )
    end

    def to_env(config) do
      (config.env ++ [{"WORKER_SECRET", config.worker_secret}])
      |> Enum.map(fn
        {k, nil} ->
          {String.to_charlist(k), false}

        {k, v} ->
          {String.to_charlist(k), String.to_charlist(v)}
      end)
    end

    defp to_arg({k, v}) do
      case {k, v} do
        {:backoff, v} ->
          ~w(--backoff #{v[:min]}/#{v[:max]})

        {:ws_url, v} ->
          ~w(--lightning #{v})

        {:capacity, v} ->
          ~w(--capacity #{v})

        {:repo_dir, v} when is_binary(v) ->
          ~w(--repo-dir #{v})

        _ ->
          [nil]
      end
    end
  end

  defmodule RuntimeClient do
    @callback start_runtime(state :: map()) :: state :: map()

    @callback stop_runtime(state :: map()) :: any()
  end

  use GenServer, restart: :transient, shutdown: 10_000
  require Logger

  defstruct runtime_port: nil,
            runtime_os_pid: nil,
            runtime_client: __MODULE__,
            buffer: [],
            config: nil

  @behaviour RuntimeClient

  def start_link(args) do
    {name, args} = Keyword.pop(args, :name, __MODULE__)

    args =
      Application.get_env(:lightning, __MODULE__, [])
      |> Keyword.merge(args)

    {config, start_args} = Config.parse(args)

    GenServer.start_link(__MODULE__, Keyword.put(start_args, :config, config),
      name: name
    )
  end

  @impl GenServer
  def init(args) do
    {start, args} = Keyword.pop(args, :start, false)

    if start do
      Process.flag(:trap_exit, true)
      state = struct(__MODULE__, args)

      {:ok, state, {:continue, :start_runtime}}
    else
      :ignore
    end
  end

  @impl GenServer
  def handle_continue(:start_runtime, %{runtime_client: runtime_client} = state) do
    {:noreply, runtime_client.start_runtime(state)}
  end

  @impl GenServer
  def handle_info({port, {:exit_status, status}}, %{runtime_port: port} = state) do
    Logger.error("Runtime exited with status: #{status}")
    # Data may arrive after exit status on line mode
    {:noreply, state, 0}
  end

  @impl GenServer
  def handle_info(:timeout, state) do
    {:stop, :premature_termination, state}
  end

  @impl GenServer
  def handle_info(
        {port, {:data, {:noeol, data}}},
        %{runtime_port: port, buffer: buffer} = state
      ) do
    {:noreply, %{state | buffer: [data | buffer]}}
  end

  @impl GenServer
  def handle_info(
        {port, {:data, {:eol, data}}},
        %{runtime_port: port, buffer: buffer} = state
      ) do
    log_buffer([data | buffer])
    {:noreply, %{state | buffer: []}}
  end

  @impl GenServer
  def handle_info(
        {port, {:data, {_, data}}},
        %{runtime_port: port, buffer: buffer} = state
      ) do
    log_buffer([data | buffer])
    {:stop, :premature_termination, %{state | buffer: []}}
  end

  @impl GenServer
  def handle_info(
        {:EXIT, port, reason},
        %{runtime_port: port} = state
      ) do
    Logger.debug("Runtime port was stopped with reason: #{reason}")

    {:stop, :premature_termination, state}
  end

  @impl GenServer
  def handle_info({:EXIT, _pid, reason}, state) do
    {:stop, reason, state}
  end

  @impl GenServer
  def terminate(
        reason,
        %{runtime_client: runtime_client} = state
      ) do
    Task.async(fn ->
      if reason not in [:timeout, :premature_termination] and
           state.runtime_port do
        Port.connect(state.runtime_port, self())
        runtime_client.stop_runtime(state)
        handle_pending_msg(state.runtime_port, state.buffer)
      end
    end)
    |> Task.await(:infinity)

    state
  end

  @impl RuntimeClient
  def start_runtime(state) do
    # If you are starting an instance of ws-worker via this Runtime Manager,
    # we are assuming that you're in dev mode and have want mix phx.server
    # to manage your NodeJs worker app, which is configured to run on port
    # 2222. Since it's not always possible to kill that app, we'll ensure it's
    # dead here in startup.
    # EDIT: This is no longer needed when using: `node ./node_modules/.bin/worker`
    # Source: https://stackoverflow.com/questions/75594758/sigterm-not-intercepted-by-the-handler-in-nodejs-app
    # System.shell("kill $(lsof -n -i :2222 | grep LISTEN | awk '{print $2}')")

    wrapper = Application.app_dir(:lightning, "priv/runtime/port_wrapper")
    init_cmd = port_init(wrapper)

    opts =
      [
        :use_stdio,
        :exit_status,
        :binary,
        :hide,
        cd: state.config.cd,
        args: state.config |> Config.to_args(),
        line: 1024,
        env: state.config |> Config.to_env()
      ]

    port = Port.open(init_cmd, opts)
    {:os_pid, os_pid} = Port.info(port, :os_pid)
    :persistent_term.put(:runtime_os_pid, os_pid)

    %{state | runtime_port: port, runtime_os_pid: os_pid}
  end

  @impl RuntimeClient
  def stop_runtime(state) do
    System.cmd("kill", ["-TERM", "#{state.runtime_os_pid}"])
  end

  defp handle_pending_msg(port, buffer) do
    receive do
      {^port, {:exit_status, status}} ->
        receive do
          {^port, {:data, {_, data}}} ->
            log_buffer([data | buffer])
            status
        after
          0 -> status
        end

      {^port, {:data, {:noeol, data}}} ->
        handle_pending_msg(port, [data | buffer])

      {^port, {:data, {:eol, data}}} ->
        log_buffer([data | buffer])
        handle_pending_msg(port, [])
    end
  end

  defp log_buffer(buffer) do
    buffer |> Enum.reverse() |> IO.iodata_to_binary() |> Logger.info()
  end

  defp port_init(command) when is_binary(command) do
    cmd = String.to_charlist(command)

    cmd =
      if Path.type(cmd) == :absolute do
        cmd
      else
        :os.find_executable(cmd) || :erlang.error(:enoent, [command])
      end

    {:spawn_executable, cmd}
  end
end
