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

    * `:start` - flag to start the runtime manager. If `false` the genserver won't be started

    * `:cacerts_path` - the directory to find certificates for
      https connections

    * `:path` - the path to find the runtime executable at. By
      default, it is automatically downloaded and placed inside
      the `_build` directory of your current app

  Overriding the `:path` is not recommended, as we will automatically
  download and manage the `runtime` for you.


  """

  use GenServer, restart: :transient, shutdown: 10_000
  require Logger

  defstruct [
    :runtime_port,
    :runtime_os_pid,
    buffer: []
  ]

  def start_link(args) do
    if config()[:start] && is_nil(config()[:version]) do
      Logger.warning("""
      runtime version is not configured. Please set it in your config files:

          config :lightning, #{__MODULE__}, version: "#{latest_version()}"
      """)
    end

    configured_version = configured_version()

    case bin_version() do
      {:ok, ^configured_version} ->
        :ok

      {:ok, version} ->
        Logger.warning("""
        Outdated runtime version. Expected #{configured_version}, got #{version}. \
        Please run `mix lightning.runtime.install` or update the version in your config files.\
        """)

      :error ->
        :ok
    end

    {name, args} = Keyword.pop(args, :name, __MODULE__)
    GenServer.start_link(__MODULE__, args, name: name)
  end

  @doc """
  Returns the path to the executable.

  The executable may not be available if it was not yet installed.
  """
  def bin_path do
    # name = "lightning-runtime-#{target()}"
    name = "lightning-runtime"

    config()[:path] ||
      if Code.ensure_loaded?(Mix.Project) do
        Path.join(Path.dirname(Mix.Project.build_path()), name)
      else
        Path.expand("_build/#{name}")
      end
  end

  @doc """
  Returns the version of the runtime executable.

  Returns `{:ok, version_string}` on success or `:error` when the executable
  is not available.
  """
  def bin_version do
    path = bin_path()

    with true <- File.exists?(path),
         {result, 0} <- System.cmd(path, ["--version"], env: %{}) do
      {:ok, String.trim(result)}
    else
      _ -> :error
    end
  end

  @doc false
  # Latest known version at the time of publishing.
  def latest_version, do: @latest_version

  @doc """
  Returns the configured runtime version.
  """
  def configured_version do
    Keyword.get(config(), :version, latest_version())
  end

  defp config do
    Application.get_env(:lightning, __MODULE__, [])
  end

  # NOTE: it hasnt yet been decided on the naming convention for the binary
  # commented to wait for the binary
  # defp target do
  #   case :os.type() do
  #     # Assuming it's an x86 CPU
  #     {:win32, _} ->
  #       windows_target()

  #     {:unix, osname} ->
  #       arch_str = :erlang.system_info(:system_architecture)
  #       [arch | _] = arch_str |> List.to_string() |> String.split("-")

  #       try do
  #         unix_target(arch, osname)
  #       rescue
  #         CaseClauseError ->
  #           reraise(
  #             "lightning-runtime is not available for architecture: #{arch_str}",
  #             __STACKTRACE__
  #           )
  #       end
  #   end
  # end

  # defp unix_target(arch, osname) do
  #   case arch do
  #     "amd64" ->
  #       "#{osname}-x64"

  #     "x86_64" ->
  #       "#{osname}-x64"

  #     "i686" ->
  #       "#{osname}-ia32"

  #     "i386" ->
  #       "#{osname}-ia32"

  #     "aarch64" ->
  #       "#{osname}-arm64"

  #     "arm" when osname == :darwin ->
  #       "darwin-arm64"

  #     "arm" ->
  #       "#{osname}-arm"

  #     "armv7" <> _ ->
  #       "#{osname}-arm"
  #   end
  # end

  # defp windows_target do
  #   wordsize = :erlang.system_info(:wordsize)

  #   if wordsize == 8 do
  #     "win32-x64"
  #   else
  #     "win32-ia32"
  #   end
  # end

  @impl true
  def init(_args) do
    if config()[:start] do
      Process.flag(:trap_exit, true)
      {:ok, %__MODULE__{}, {:continue, :start_runtime}}
    else
      :ignore
    end
  end

  @impl true
  def handle_continue(:start_runtime, state) do
    {:noreply, start_runtime(state)}
  end

  @impl true
  def handle_info({port, {:exit_status, status}}, %{runtime_port: port} = state) do
    Logger.error("Runtime exited with status: #{status}")
    # Data may arrive after exit status on line mode
    {:noreply, state, 0}
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

  def handle_info({:EXIT, port, reason}, %{runtime_port: port} = state) do
    Logger.debug("Runtime port was stopped with reason: #{reason}")
    {:stop, :premature_termination, state}
  end

  def handle_info({:EXIT, _pid, reason}, state) do
    {:stop, reason, state}
  end

  @impl true
  def terminate(reason, state) do
    Task.async(fn ->
      port = state.runtime_port
      os_pid = state.runtime_os_pid

      if reason not in [:timeout, :premature_termination] and state.runtime_port do
        Port.connect(port, self())
        System.cmd("kill", ["-TERM", "#{os_pid}"], into: "", env: %{})
        handle_pending_msg(port, state.buffer)
      end
    end)
    |> Task.await(:infinity)

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
        [:use_stdio, :exit_status, :binary, :hide] ++
          [args: [bin_path() | args], line: 1024]
      )

    port = Port.open(init_cmd, opts)
    {:os_pid, os_pid} = Port.info(port, :os_pid)
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
