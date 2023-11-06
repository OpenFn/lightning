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

  use GenServer, restart: :transient, shutdown: 10_000
  require Logger

  defstruct runtime_port: nil,
            runtime_os_pid: nil,
            shutdown: false,
            buffer: []

  @sigterm_status 143

  @impl true
  def init(_args) do
    if config()[:start] do
      Process.flag(:trap_exit, true)
      {:ok, %__MODULE__{}, {:continue, :start_runtime}}
    else
      :ignore
    end
  end

  def start_link(args) do
    {name, args} = Keyword.pop(args, :name, __MODULE__)
    GenServer.start_link(__MODULE__, args, name: name)
  end

  defp config do
    Application.get_env(:lightning, __MODULE__, [])
  end

  @impl true
  def handle_continue(:start_runtime, state) do
    {:noreply, start_runtime(state)}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{runtime_port: port} = state) do
    Logger.error("Runtime exited with status: #{status}")
    # Data may arrive after exit status on line mode
    {:noreply, %{state | shutdown: status == @sigterm_status}, 0}
  end

  def handle_info(:timeout, state) do
    {:stop, :premature_termination, state}
  end

  def handle_info(
        {port, {:data, {:noeol, data}}},
        %{runtime_port: port, buffer: buffer} = state
      ) do
    {:noreply, %{state | buffer: [data | buffer]}}
  end

  def handle_info(
        {port, {:data, {:eol, data}}},
        %{runtime_port: port, buffer: buffer} = state
      ) do
    log_buffer([data | buffer])
    {:noreply, %{state | buffer: []}}
  end

  def handle_info(
        {port, {:data, {_, data}}},
        %{runtime_port: port, buffer: buffer} = state
      ) do
    log_buffer([data | buffer])
    {:stop, :premature_termination, %{state | buffer: []}}
  end

  def handle_info(
        {:EXIT, port, reason},
        %{runtime_port: port, shutdown: shutdown?} = state
      ) do
    Logger.debug("Runtime port was stopped with reason: #{reason}")

    if shutdown? do
      {:noreply, %{state | runtime_port: nil, runtime_os_pid: nil}}
    else
      {:stop, :premature_termination, state}
    end
  end

  def handle_info({:EXIT, _pid, reason}, state) do
    {:stop, reason, state}
  end

  @impl true
  def terminate(reason, %{shutdown: shutdown?} = state) do
    unless shutdown? do
      Task.async(fn ->
        port = state.runtime_port
        os_pid = state.runtime_os_pid

        if reason not in [:timeout, :premature_termination] and
             state.runtime_port do
          Port.connect(port, self())
          System.cmd("kill", ["-TERM", "#{os_pid}"])
          handle_pending_msg(port, state.buffer)
        end
      end)
      |> Task.await(:infinity)
    end

    state
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

  defp start_runtime(state) do
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
