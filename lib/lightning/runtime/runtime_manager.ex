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

  defmodule RuntimeClient do
    @callback start_runtime(state :: map()) :: state :: map()

    @callback stop_runtime(state :: map()) :: any()
  end

  use GenServer, restart: :transient, shutdown: 10_000
  require Logger

  defstruct runtime_port: nil,
            runtime_os_pid: nil,
            runtime_client: nil,
            buffer: []

  @behaviour RuntimeClient

  def start_link(args) do
    {name, args} = Keyword.pop(args, :name, __MODULE__)
    start_args = Keyword.merge(config(), args)
    GenServer.start_link(__MODULE__, start_args, name: name)
  end

  @impl GenServer
  def init(args) do
    {start, args} = Keyword.pop(args, :start, false)

    if start do
      Process.flag(:trap_exit, true)
      module = Keyword.get(args, :runtime_client, __MODULE__)
      {:ok, %__MODULE__{runtime_client: module}, {:continue, :start_runtime}}
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

    config = config()
    {args, start_opts} = Keyword.pop(config, :args, [])
    start_opts = Keyword.take(start_opts, [:cd, :env])

    wrapper = Application.app_dir(:lightning, "priv/runtime/port_wrapper")
    init_cmd = port_init(wrapper)

    opts =
      cmd_opts(
        start_opts,
        [
          :use_stdio,
          :exit_status,
          :binary,
          :hide,
          args: args,
          line: 1024,
          env: [
            {~c"WORKER_SECRET",
             Application.get_env(:lightning, :workers, [])
             |> Keyword.get(:worker_secret)
             |> to_charlist()}
          ]
        ]
      )

    port = Port.open(init_cmd, opts)
    {:os_pid, os_pid} = Port.info(port, :os_pid)
    :persistent_term.put(:runtime_os_pid, os_pid)

    %{state | runtime_port: port, runtime_os_pid: os_pid}
  end

  @impl RuntimeClient
  def stop_runtime(state) do
    System.cmd("kill", ["-TERM", "#{state.runtime_os_pid}"])
  end

  defp config do
    Application.get_env(:lightning, __MODULE__, [])
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

  defp cmd_opts([{:cd, bin} | t], opts) when is_binary(bin),
    do: cmd_opts(t, [{:cd, bin} | opts])

  defp cmd_opts([{:env, enum} | t], opts),
    do: cmd_opts(t, [{:env, validate_env(enum)} | opts])

  defp cmd_opts([], opts), do: opts

  defp validate_env(enum) do
    Enum.map(enum, fn
      {k, nil} ->
        {String.to_charlist(k), false}

      {k, v} ->
        {String.to_charlist(k), String.to_charlist(v)}
    end)
  end
end
