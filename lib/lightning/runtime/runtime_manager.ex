defmodule Lightning.Runtime.RuntimeManager do
  @moduledoc """
  Locates and runs the Runtime server. Added in order to ease development and default installations of Lightning
  """

  use GenServer, restart: :permanent, shutdown: 10_000
  require Logger

  alias __MODULE__

  defstruct [
    :lightning_url,
    :runtime_port,
    :runtime_os_pid,
    :env,
    args: [Application.app_dir(:lightning, "priv/runtime/logger.js")],
    runtime_path: "/Users/frank/.asdf/shims/node",
    buffer: []
  ]

  def start_link(args) do
    {name, args} = Keyword.pop(args, :name, __MODULE__)
    GenServer.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init(args) do
    Process.flag(:trap_exit, true)
    config = Application.get_env(:lighting, RuntimeManager, [])
    config = Keyword.merge(config, args)

    config = Keyword.put_new(config, :lightning_url, LightningWeb.Endpoint.url())

    {:ok, struct(RuntimeManager, config), {:continue, :start_runtime}}
  end

  @impl true
  def handle_continue(:start_runtime, state) do
    {:noreply, start_runtime(state)}
  end

  @impl true

  def handle_info({port, {:exit_status, status}}, %{runtime_port: port} = state) do
    Logger.debug("Runtime exited with status: #{status}")
    # Data may arrive after exit status on line mode
    {:noreply, state, 1}
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
    [data | buffer] |> Enum.reverse() |> IO.iodata_to_binary() |> Logger.info()
    {:noreply, %{state | buffer: []}}
  end

  def handle_info(
        {port, {:data, {_, data}}},
        %{runtime_port: port, buffer: buffer} = state
      ) do
    [data | buffer] |> Enum.reverse() |> IO.iodata_to_binary() |> Logger.info()
    {:stop, %{state | buffer: []}, :premature_termination}
  end

  def handle_info(
        {:DOWN, _ref, :port, port, reason},
        %{runtime_port: port} = state
      ) do
    Logger.debug("Runtime port was stopped with reason: #{reason}")
    {:stop, :premature_termination, state}
  end

  def handle_info({:EXIT, port, reason}, %{runtime_port: port} = state) do
    Logger.debug("Runtime port was stopped with reason: #{reason}")
    {:stop, :premature_termination, state}
  end

  @impl true
  def terminate(reason, state) do
    Logger.info("Shutting down Runtime Manager with reason: #{inspect(reason)}")

    Task.async(fn ->
      port = state.runtime_port
      os_pid = state.runtime_os_pid

      if reason not in [:timeout, :premature_termination] do
        Port.connect(port, self())
        System.cmd("kill", ["-TERM", "#{os_pid}"], into: "")
        handle_pending_msg(port, state.buffer)
      end
    end)
    |> Task.await(10_000)

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

  defp start_runtime(config) do
    wrapper = Application.app_dir(:lightning, "priv/runtime/wrapper")
    init_cmd = port_init(wrapper)

    opts =
      cmd_opts(
        [lines: 1024],
        [:use_stdio, :exit_status, :binary, :hide] ++
          [args: [config.runtime_path | config.args]]
      )

    port = Port.open(init_cmd, opts)
    Port.monitor(port)
    {:os_pid, os_pid} = Port.info(port, :os_pid)
    IO.inspect(os_pid, label: "================> OS PID For Runtime")
    %{config | runtime_port: port, runtime_os_pid: os_pid}
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

  defp cmd_opts([{:stderr_to_stdout, true} | t], opts),
    do: cmd_opts(t, [:stderr_to_stdout | opts])

  defp cmd_opts([{:stderr_to_stdout, false} | t], opts),
    do: cmd_opts(t, opts)

  defp cmd_opts([{:env, enum} | t], opts),
    do: cmd_opts(t, [{:env, validate_env(enum)} | opts])

  defp cmd_opts([{:lines, max_line_length} | t], opts)
       when is_integer(max_line_length) and max_line_length > 0,
       do: cmd_opts(t, [{:line, max_line_length} | opts])

  defp cmd_opts([{key, val} | _], _opts),
    do:
      raise(
        ArgumentError,
        "invalid option #{inspect(key)} with value #{inspect(val)}"
      )

  defp cmd_opts([], opts), do: opts

  defp validate_env(enum) do
    Enum.map(enum, fn
      {k, nil} ->
        {String.to_charlist(k), false}

      {k, v} ->
        {String.to_charlist(k), String.to_charlist(v)}

      other ->
        raise ArgumentError, "invalid environment key-value #{inspect(other)}"
    end)
  end
end
