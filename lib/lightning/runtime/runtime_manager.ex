defmodule Lightning.Runtime.RuntimeManager do
  # https://registry.npmjs.org/@openfn/ws-worker/latest
  @latest_version "0.1.1"

  @moduledoc """
  RuntimeManager is an installer and runner for [ws-worker](https://www.github.com/openfn/kit/packages/ws-worker).

  ## RuntimeManager configuration

      config :lightning, Lightning.Runtime.RuntimeManager,
        start: true,
        version: "0.1.1"

  There are three global configurations for the RuntimeManager application:

    * `:version` - the expected ws-worker version

    * `:cacerts_path` - the directory to find certificates for
      https connections

    * `:path` - the path to find the ws-worker executable at. By
      default, it is automatically downloaded and placed inside
      the `_build` directory of your current app

  Overriding the `:path` is not recommended, as we will automatically
  download and manage `ws-worker` for you. But in case you can't download
  it (for example, the npm registry is behind a proxy), you may want to
  set the `:path` to a configurable system location.

  """

  use GenServer, restart: :transient, shutdown: 10_000
  require Logger

  defstruct [
    :runtime_port,
    :runtime_os_pid,
    buffer: []
  ]

  @impl true
  def init(_args) do
    if config()[:start] do
      Process.flag(:trap_exit, true)
      {:ok, %__MODULE__{}, {:continue, :install_and_run}}
    else
      :ignore
    end
  end

  @impl true
  def handle_continue(:install_and_run, state) do
    {:noreply, install_and_run(state)}
  end

  @doc false
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

      # TODO: update install_runtime
      {:ok, version} ->
        Logger.warning("""
        Outdated ws-worker version. Expected #{configured_version}, got #{version}. \
        Please run `mix lightning.install_runtime` or update the version in your config files.\
        """)

      :error ->
        :ok
    end

    {name, args} = Keyword.pop(args, :name, __MODULE__)
    GenServer.start_link(__MODULE__, args, name: name)
  end

  @doc false
  # Latest known version at the time of publishing.
  def latest_version, do: @latest_version

  @doc """
  Returns the configured ws-worker version.
  """
  def configured_version do
    Application.get_env(:worker, :version, latest_version())
  end

  @doc """
  Returns the configuration for the given profile.

  Returns nil if the profile does not exist.
  """
  def config_for!(profile) when is_atom(profile) do
    Application.get_env(:worker, profile) ||
      raise ArgumentError, """
      unknown esbuild profile. Make sure the profile is defined in your config/config.exs file, such as:

          config :esbuild,
            #{profile}: [
              args: ~w(js/app.js --bundle --target=es2016 --outdir=../priv/static/assets),
              cd: Path.expand("../assets", __DIR__),
              env: %{"NODE_PATH" => Path.expand("../deps", __DIR__)}
            ]
      """
  end

  defp config do
    Application.get_env(:lightning, __MODULE__, [])
  end

  @doc """
  Returns the path to the executable.

  The executable may not be available if it was not yet installed.
  """
  def bin_path do
    # TODO: support other architectures
    # name = "@openfn/ws-worker-#{target()}"
    name = "@openfn/ws-worker"

    Application.get_env(:worker, :path) ||
      if Code.ensure_loaded?(Mix.Project) do
        Path.join(Path.dirname(Mix.Project.build_path()), name)
      else
        Path.expand("_build/#{name}")
      end
  end

  @doc """
  Returns the version of the esbuild executable.

  Returns `{:ok, version_string}` on success or `:error` when the executable
  is not available.
  """
  def bin_version do
    path = bin_path()

    with true <- File.exists?(path),
         {result, 0} <- System.cmd(path, ["--version"]) do
      {:ok, String.trim(result)}
    else
      _ -> :error
    end
  end

  @doc """
  Runs the given command with `args`.

  The given args will be appended to the configured args.
  The task output will be streamed directly to stdio. It
  returns the status of the underlying call.
  """
  def run(profile, extra_args) when is_atom(profile) and is_list(extra_args) do
    config = config_for!(profile)
    args = config[:args] || []

    if args == [] and extra_args == [] do
      raise "no arguments passed to esbuild"
    end

    opts = [
      cd: config[:cd] || File.cwd!(),
      env: config[:env] || %{},
      into: IO.stream(:stdio, :line),
      stderr_to_stdout: true
    ]

    bin_path()
    |> System.cmd(args ++ extra_args, opts)
    |> elem(1)
  end

  defp start_unique_install_worker() do
    install()
    :ok
    # ref =
    #   __MODULE__.Supervisor
    #   |> Supervisor.start_child(
    #     Supervisor.child_spec({Task, &install/0},
    #       restart: :transient,
    #       id: __MODULE__.Installer
    #     )
    #   )
    #   |> case do
    #     {:ok, pid} -> pid
    #     {:error, {:already_started, pid}} -> pid
    #   end
    #   |> Process.monitor()

    # receive do
    #   {:DOWN, ^ref, _, _, _} -> :ok
    # end
  end

  defp port_init(command) when is_binary(command) do
    cmd = String.to_charlist(command)

    IO.inspect(cmd, label: "are we here?")

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

  @doc """
  Installs, if not available, and then runs `esbuild`.

  This task may be invoked concurrently and it will avoid concurrent installs.

  Returns the same as `run/2`.
  """
  def install_and_run(state) do
    config = config()
    {args, start_opts} = Keyword.pop(config, :args, [])
    start_opts = Keyword.take(start_opts, [:cd, :env])

    File.exists?(bin_path()) || start_unique_install_worker()

    wrapper = Application.app_dir(:lightning, "priv/runtime/port_wrapper")

    init_cmd =
      port_init(wrapper)

    opts =
      cmd_opts(
        start_opts,
        [:use_stdio, :exit_status, :binary, :hide] ++
          [args: [bin_path() | args], line: 1024]
      )

    IO.inspect("This will fail; TODO when we have a single file to point at.")
    port = Port.open(init_cmd, opts)
    {:os_pid, os_pid} = Port.info(port, :os_pid)
    %{state | runtime_port: port, runtime_os_pid: os_pid}
  end

  @doc """
  Installs esbuild with `configured_version/0`.

  If invoked concurrently, this task will perform concurrent installs.
  """
  def install do
    version = configured_version()
    tmp_opts = if System.get_env("MIX_XDG"), do: %{os: :linux}, else: %{}

    tmp_dir =
      freshdir_p(:filename.basedir(:user_cache, "lighting-ws-worker", tmp_opts)) ||
        freshdir_p(Path.join(System.tmp_dir!(), "lighting-ws-worker")) ||
        raise "could not install esbuild. Set MIX_XGD=1 and then set XDG_CACHE_HOME to the path you want to use as cache"

    # TODO: support other architectures?
    # name = "@openfn/ws-worker#{target()}"
    name = "@openfn/ws-worker"

    tar = Lightning.Runtime.NpmRegistry.fetch_package!(name, version)

    case :erl_tar.extract({:binary, tar}, [
           :compressed,
           cwd: to_charlist(tmp_dir)
         ]) do
      :ok -> :ok
      other -> raise "couldn't unpack archive: #{inspect(other)}"
    end

    bin_path = bin_path()
    File.mkdir_p!(Path.dirname(bin_path))

    File.cp_r!(Path.join([tmp_dir, "package"]), bin_path)
    # case :os.type() do
    #   # TODO: Support Windows users! (help wanted)
    #   {:win32, _} ->
    #     # File.cp!(Path.join([tmp_dir, "package", "esbuild.exe"]), bin_path)
    #     raise "we don't yet support Windows"

    #   _ ->
    #     File.cp!(Path.join([tmp_dir, "package", "bin", "ws-worker"]), bin_path)
    # end
  end

  defp freshdir_p(path) do
    with {:ok, _} <- File.rm_rf(path),
         :ok <- File.mkdir_p(path) do
      path
    else
      _ -> nil
    end
  end

  # # Available targets: https://github.com/evanw/esbuild/tree/main/npm/@esbuild
  # defp target do
  #   case :os.type() do
  #     # Assuming it's an x86 CPU
  #     {:win32, _} ->
  #       wordsize = :erlang.system_info(:wordsize)

  #       if wordsize == 8 do
  #         "win32-x64"
  #       else
  #         "win32-ia32"
  #       end

  #     {:unix, osname} ->
  #       arch_str = :erlang.system_info(:system_architecture)
  #       [arch | _] = arch_str |> List.to_string() |> String.split("-")

  #       case arch do
  #         "amd64" -> "#{osname}-x64"
  #         "x86_64" -> "#{osname}-x64"
  #         "i686" -> "#{osname}-ia32"
  #         "i386" -> "#{osname}-ia32"
  #         "aarch64" -> "#{osname}-arm64"
  #         _ -> raise "ws-worker is not available for architecture: #{arch_str}"
  #       end
  #   end
  # end
end
