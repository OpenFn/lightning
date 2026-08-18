defmodule Lightning.AdaptorService do
  @moduledoc """
  The Adaptor Service is use to query and install adaptors in order to run jobs.

  On startup, it queries the filesystem for `package.json` files and builds up
  a list of available adaptors.

  ## Configuration

  The service requires at least `:adaptors_path`, which is used to both query
  which adaptors are installed and when to install new adaptors.

  Another optional setting is: `:repo`, which must point at a module that will be
  used to do the querying and installing.

  ## Installing Adaptors

  Using the `install/2` function an adaptor can be installed, which will also
  add it to the list of available adaptors.

  Installing happens out-of-band via a supervised task; the caller's `install/2`
  call blocks until it completes. If a second call for the same package/version
  comes in while an install is already in flight, it's queued behind the first
  rather than starting a second, redundant install — both callers get the same
  result once it finishes. An adaptor never appears in the list, and is never
  returned from a lookup, until it's actually present on disk; there's no
  half-installed entry visible in between.

  ## Looking up adaptors

  The module leans on Elixir's built-in `Version` module to provide version
  lookups.

  When looking up an adaptor, either a string or a tuple can be used.
  In the case of requesting the latest version, any one of these will return
  the latest version the service is aware of.

  - `@openfn/language-http`
  - `@openfn/language-http@latest`
  - `{"@openfn/language-http", nil}`
  - `{"@openfn/language-http", "latest"}`
  - `{~r/language-http/, "latest"}`

  You can also request a specific version, or use a range specification:

  - `@openfn/language-http@1.2.3`
  - `{"@openfn/language-http", "~> 1.2.0"}`
  - `{"@openfn/language-http", "< 2.0.0"}`

  > **NOTE**
  > More complex npm style install strings like: `">=0.1.0 <0.2.0"`
  > are not supported.
  > Generally the tuple style is preferred when using range specifications as
  > the npm style strings have a simplistic regex splitter.

  A version that isn't valid semver (and isn't `latest`) never raises here —
  it's simply treated as not matching anything, since neither a stored nor a
  requested version can be trusted to be well-formed (locally-linked adaptors
  in particular can report a non-semver version like `local`).

  See [Version](https://hexdocs.pm/elixir/Version.html) for more details on
  matching versions.
  """
  use GenServer

  alias Lightning.AdaptorRegistry

  require Logger

  defmodule Adaptor do
    @moduledoc false
    @type install_status :: :present

    @type t :: %__MODULE__{
            name: binary(),
            version: binary(),
            path: binary(),
            status: install_status(),
            local_name: binary()
          }

    @enforce_keys [:name, :version]
    defstruct @enforce_keys ++ [:status, :path, :local_name]
  end

  defmodule Repo do
    @moduledoc false
    require Logger

    @doc """
    List all adaptors in the given directory.

    This function is called when the service starts up in order to query
    which adaptors are already installed.
    """
    @callback list_local(path :: String.t()) :: list(Adaptor.t())
    def list_local(path, _depth \\ 4) when is_binary(path) do
      System.cmd("npm", ~w[list --global --json --long --prefix #{path}],
        env: []
      )
      |> case do
        {stdout, 0} ->
          stdout
          |> String.trim()
          |> Jason.decode!()
          |> Map.get("dependencies", %{})
          |> Map.filter(fn {local_name, _} ->
            local_name |> String.starts_with?("@openfn")
          end)
          |> Enum.map(fn {local_name, details} ->
            %Adaptor{
              name: details["name"],
              version: details["version"],
              path: details["path"],
              local_name: local_name,
              status: :present
            }
          end)

        {_, 254} ->
          Logger.error("""
          Ensure the adaptors path is correct or run:

          mix lightning.install_runtime

          To create the initial folder structure.
          """)

          raise "No such directory: #{path}"

        {stdout, _} ->
          raise "Failed to list adaptors from path: #{path}\n#{stdout}"
      end
    end

    @doc """
    ```
    |------------ alias ---------| |----- source &|| version -------|
    @openfn/language-common-v1.2.6@npm:@openfn/language-common@1.2.6
    ```
    """
    @callback install(
                adaptors :: list(String.t()) | String.t(),
                dir :: String.t()
              ) ::
                {Collectable.t(), exit_status :: non_neg_integer}
    @spec install(adaptors :: list(String.t()) | String.t(), dir :: String.t()) ::
            {Collectable.t(), exit_status :: non_neg_integer}
    def install(adaptor, dir) when is_binary(adaptor),
      do: install([adaptor], dir)

    def install(adaptors, dir) when is_list(adaptors) do
      System.cmd(
        "npm",
        [
          "install",
          "--no-save",
          "--ignore-scripts",
          "--no-fund",
          "--no-audit",
          "--no-package-lock",
          "--global",
          "--prefix",
          dir | adaptors
        ],
        env: [],
        stderr_to_stdout: true
      )
    end

    @doc """
    Given a list of _potentially_ nested package.json files (i.e. dependencies of
    our adaptors), `filter_parent_paths/1` reduces the list down to the parent
    directories by grouping directory names by their shortest common path.
    """
    def filter_parent_paths(paths) when is_list(paths) do
      paths
      |> Enum.sort(:desc)
      |> Enum.reduce([], fn path, acc ->
        base = path |> String.replace("package.json", "")

        parent =
          acc
          |> Enum.find(base, fn parent -> String.contains?(base, parent) end)

        acc ++ [parent]
      end)
      |> Enum.uniq()
      |> Enum.map(fn folder -> "#{folder}package.json" end)
    end
  end

  @type package_spec ::
          {name :: String.t() | Regex.t(), version :: String.t() | nil}

  # No `install/2` call is expected to wait longer than this for an in-flight
  # (its own, or someone else's overlapping) install to finish. Generous on
  # purpose: this mirrors the previous implementation, where the actual `npm
  # install` ran unbounded in the caller's own process with no timeout at all.
  @install_timeout :timer.minutes(5)

  defmodule State do
    @moduledoc false

    @type t :: %__MODULE__{
            name: GenServer.server(),
            adaptors: [Adaptor.t()],
            adaptors_path: binary(),
            repo: module(),
            adaptor_registry: GenServer.server(),
            task_sup: pid() | nil,
            # package_spec => [GenServer.from()] — callers waiting on an
            # in-flight install for that exact spec.
            pending: %{Lightning.AdaptorService.package_spec() => list()},
            # Task ref => package_spec, so a completed/crashed install can be
            # matched back to who's waiting on it.
            installs: %{reference() => Lightning.AdaptorService.package_spec()}
          }

    @enforce_keys [:adaptors_path]
    defstruct @enforce_keys ++
                [
                  :name,
                  :task_sup,
                  adaptors: [],
                  repo: Repo,
                  adaptor_registry: Lightning.AdaptorRegistry,
                  pending: %{},
                  installs: %{}
                ]

    def refresh_list(state) do
      %{state | adaptors: state.repo.list_local(state.adaptors_path)}
    end
  end

  def start_link(opts) do
    {:ok, task_sup} = Task.Supervisor.start_link()

    state =
      opts
      |> Keyword.put(:task_sup, task_sup)
      |> then(&struct!(State, &1))
      |> State.refresh_list()

    GenServer.start_link(__MODULE__, state, name: state.name || __MODULE__)
  end

  @impl true
  def init(state), do: {:ok, state}

  def get_adaptors(agent) do
    GenServer.call(agent, :get_adaptors)
  end

  @spec find_adaptor(GenServer.server(), package :: String.t()) ::
          Adaptor.t() | nil
  def find_adaptor(agent, package) when is_binary(package) do
    find_adaptor(agent, resolve_package_name(package))
  end

  @spec find_adaptor(GenServer.server(), package_spec()) :: Adaptor.t() | nil
  def find_adaptor(agent, {_package_name, _version} = package_spec) do
    GenServer.call(agent, {:find_adaptor, package_spec})
  end

  def installed?(agent, package_spec) do
    !!find_adaptor(agent, package_spec)
  end

  @spec install(GenServer.server(), binary()) ::
          {:ok, Adaptor.t()}
          | {:error, :adaptor_not_permitted}
          | {:error, {Collectable.t(), exit_status :: non_neg_integer}}
  def install(agent, package) when is_binary(package) do
    install(agent, resolve_package_name(package))
  end

  @spec install(GenServer.server(), package_spec()) ::
          {:ok, Adaptor.t()}
          | {:error, :adaptor_not_permitted}
          | {:error, {Collectable.t(), exit_status :: non_neg_integer}}
  def install(agent, {_package_name, _version} = package_spec) do
    GenServer.call(agent, {:install, package_spec}, @install_timeout)
  end

  @impl true
  def handle_call(:get_adaptors, _from, state) do
    {:reply, state.adaptors, state}
  end

  def handle_call({:find_adaptor, package_spec}, _from, state) do
    {:reply, find_in(state.adaptors, package_spec), state}
  end

  def handle_call(
        {:install, {package_name, _version} = package_spec},
        from,
        state
      ) do
    if AdaptorRegistry.exists?(state.adaptor_registry, package_name) do
      do_install(package_spec, from, state)
    else
      Logger.warning(
        "Refusing to install non-permitted adaptor: #{inspect(package_name)}"
      )

      {:reply, {:error, :adaptor_not_permitted}, state}
    end
  end

  # Already on disk — reply immediately, nothing to install.
  defp do_install(package_spec, from, state) do
    case find_in(state.adaptors, package_spec) do
      %Adaptor{} = existing ->
        {:reply, {:ok, existing}, state}

      nil ->
        already_installing? = Map.has_key?(state.pending, package_spec)

        state =
          update_in(state.pending[package_spec], fn
            nil -> [from]
            froms -> [from | froms]
          end)

        state =
          if already_installing?,
            do: state,
            else: start_install(state, package_spec)

        {:noreply, state}
    end
  end

  defp start_install(state, package_spec) do
    %Task{ref: ref} =
      Task.Supervisor.async_nolink(state.task_sup, fn ->
        state.repo.install(build_aliased_name(package_spec), state.adaptors_path)
      end)

    put_in(state.installs[ref], package_spec)
  end

  @impl true
  def handle_info({ref, result}, %{installs: installs} = state)
      when is_reference(ref) do
    case Map.pop(installs, ref) do
      {nil, _installs} ->
        # Not one of ours (or already handled) — ignore.
        {:noreply, state}

      {package_spec, installs} ->
        Process.demonitor(ref, [:flush])
        {froms, pending} = Map.pop(state.pending, package_spec, [])

        {reply, adaptors} =
          case result do
            {_stdout, 0} ->
              Logger.info("Refreshing Adaptor list")
              adaptors = state.repo.list_local(state.adaptors_path)
              {{:ok, find_in(adaptors, package_spec)}, adaptors}

            {stdout, code} ->
              {{:error, {stdout, code}}, state.adaptors}
          end

        Enum.each(froms, &GenServer.reply(&1, reply))

        {:noreply,
         %{state | installs: installs, pending: pending, adaptors: adaptors}}
    end
  end

  def handle_info(
        {:DOWN, ref, :process, _pid, reason},
        %{installs: installs} = state
      ) do
    case Map.pop(installs, ref) do
      {nil, _installs} ->
        {:noreply, state}

      {package_spec, installs} ->
        {froms, pending} = Map.pop(state.pending, package_spec, [])

        Enum.each(
          froms,
          &GenServer.reply(&1, {:error, {:install_crashed, reason}})
        )

        {:noreply, %{state | installs: installs, pending: pending}}
    end
  end

  # Every entry ever added to `state.adaptors` is `:present` (there's no
  # half-installed placeholder anymore, see `do_install/3`), so a version
  # that survives `by_name_and_requirement/3`'s filter below is always valid
  # semver, and `Version.parse!/1` here can't raise.
  defp find_in(adaptors, {package_name, version}) do
    case version_to_requirement(version) do
      :no_match ->
        nil

      requirement ->
        adaptors
        |> Enum.filter(&by_name_and_requirement(&1, package_name, requirement))
        |> Enum.max_by(
          fn %{version: version} -> Version.parse!(version) end,
          Version,
          fn -> nil end
        )
    end
  end

  defp by_name_and_requirement(adaptor, %Regex{} = matcher, requirement) do
    Regex.match?(matcher, adaptor.name) &&
      version_matches?(adaptor.version, requirement)
  end

  defp by_name_and_requirement(adaptor, name, requirement) do
    match?(%{name: ^name}, adaptor) &&
      version_matches?(adaptor.version, requirement)
  end

  # A stored adaptor version is data, not something we control (it comes from
  # `npm list`'s output, and a locally-linked adaptor in particular can report
  # a non-semver version like "local"). Never let a version we can't parse
  # raise here — it simply doesn't match anything.
  defp version_matches?(version, requirement) do
    case Version.parse(version) do
      {:ok, parsed} -> Version.match?(parsed, requirement, allow_pre: false)
      :error -> false
    end
  end

  # A requested version is also not guaranteed to be well-formed — same
  # non-raising treatment as `version_matches?/2` above, just on the
  # requirement side instead of the stored side.
  defp version_to_requirement(version) do
    spec =
      cond do
        version in ["latest", nil] ->
          "> 0.0.0"

        String.match?(version, ~r/[<=>]/) ->
          raise ArgumentError, message: "Version specs not implemented yet."

        true ->
          "== #{version}"
      end

    case Version.parse_requirement(spec) do
      {:ok, requirement} -> requirement
      :error -> :no_match
    end
  end

  def resolve_package_name(package_name) when is_binary(package_name) do
    AdaptorRegistry.adaptor_format()
    |> Regex.run(package_name)
    |> case do
      [_, name, version] -> {name, version}
      [_, name] -> {name, nil}
      _ -> {nil, nil}
    end
  end

  @doc """
  Turns a package name and version into a string for NPM.

  Since multiple versions of the same package can be installed, it's important
  to rely on npms built-in package aliasing.

  E.g. `@openfn/language-http@1.2.8` turns into:
       `@openfn/language-http-1.2.8@npm:@openfn/language-http@1.2.8`

  Which is pretty long winded but necessary for the reason above.

  If using this module as a base, it's likely you would need to adaptor this
  to suit your particular naming strategy.
  """
  def build_aliased_name({package, version}) do
    "#{package}-#{version || "latest"}@npm:#{package}@#{version || "latest"}"
  end
end
