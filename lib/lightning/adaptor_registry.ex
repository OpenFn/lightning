defmodule Lightning.AdaptorRegistry do
  @moduledoc """
  Registry process to query and maintain a list of adaptors available for
  writing jobs.

  Currently it queries NPM for all modules in the `@openfn` organization and
  filters out modules that are known not to be adaptors.

  **Usage**

  ```
  # Starting the process
  AdaptorRegistry.start_link()
  # Getting a list of all adaptors
  Lightning.AdaptorRegistry.AdaptorRegistry.all()
  ```

  **Caching**

  By default the results are cached to disk, and will be reused every start.

  In order to disable or configure caching pass see: `start_link/1`.

  The process uses `:continue` to return before the adaptors have been queried.
  This does mean that the first call to the process will be delayed until
  the `handle_continue/2` has finished.

  **Timeouts**

  There is a 'general' timeout of 30s, this is used for GenServer calls like
  `all/1` and also internally when the modules are being queried. NPM can
  be extremely fast to respond if the package is cached on their side, but
  can take a couple of seconds if not cached.
  """

  use GenServer
  require Logger

  @excluded_adaptors ["@openfn/language-devtools", "@openfn/language-template"]
  @timeout 30_000

  defmodule Npm do
    @moduledoc """
    NPM API functions
    """
    use HTTPoison.Base

    @impl true
    def process_request_url(url) do
      "https://registry.npmjs.org" <> url
    end

    @impl true
    def process_response_body(body) do
      body
      |> Jason.decode!()
    end

    @doc """
    Retrieve all packages for a given user or organization. Return empty list if
    application cannot connect to NPM. (E.g., because it's started offline.)
    """
    @spec user_packages(user :: String.t()) :: [map()]
    def user_packages(user) do
      get("/-/user/#{user}/package", [],
        hackney: [pool: :default],
        recv_timeout: 15_000
      )
      |> case do
        {:error, %HTTPoison.Error{reason: :nxdomain, id: nil}} ->
          Logger.info("Unable to connect to NPM; no adaptors fetched.")
          []

        {:ok, resp} ->
          Map.get(resp, :body)
      end
    end

    @doc """
    Retrieve all details for an NPM package
    """
    @spec package_detail(package_name :: String.t()) :: map()
    def package_detail(package_name) do
      get!("/#{package_name}", [],
        hackney: [pool: :default],
        recv_timeout: 15_000
      ).body
    end
  end

  @impl GenServer
  def init(opts) do
    {:ok, [], {:continue, opts}}
  end

  @impl GenServer
  def handle_continue(opts, _state) do
    cache_path =
      case opts[:use_cache] do
        true -> "tmp/adaptor_registry_cache.json"
        path when is_binary(path) -> path
        _ -> nil
      end

    if cache_path do
      read_from_cache(cache_path)
      |> case do
        nil ->
          {:noreply, write_to_cache(cache_path, fetch())}

        adaptors ->
          {:noreply, adaptors}
      end
    else
      {:noreply, fetch()}
    end
  end

  # false positive, it's a file from init
  # sobelow_skip ["Traversal.FileModule"]
  defp write_to_cache(path, adaptors) when is_binary(path) do
    File.mkdir("tmp")
    cache_file = File.open!(path, [:write])
    IO.binwrite(cache_file, Jason.encode_to_iodata!(adaptors))
    File.close(cache_file)

    adaptors
  end

  # false positive, it's a file from init
  # sobelow_skip ["Traversal.FileModule"]
  defp read_from_cache(path) when is_binary(path) do
    File.read(path)
    |> case do
      {:ok, file} -> Jason.decode!(file, keys: :atoms!)
      {:error, _} -> nil
    end
  end

  @doc """
  Starts the AdaptorRegistry

  **Options**

  - `:use_cache` (defaults to false) - stores the last set of results on disk
    and uses the cached file for every subsequent start.
    It can either be a boolean, or a string - the latter being a file path
    to set where the cache file is located.
  - `:name` (defaults to AdaptorRegistry) - the name of the process, useful
    for testing and/or running multiple versions of the registry
  """
  @spec start_link(opts :: [use_cache: boolean() | binary(), name: term()]) ::
          {:error, any} | {:ok, pid}
  def start_link(opts \\ [use_cache: true]) do
    Logger.info("Starting AdaptorRegistry")
    {name, opts} = Keyword.pop(opts, :name, __MODULE__)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl GenServer
  def handle_call(:all, _from, state) do
    {:reply, state, state}
  end

  @impl GenServer
  def handle_call({:versions_for, module_name}, _from, state) do
    versions =
      state
      |> Enum.find(fn %{name: name} -> name == module_name end)
      |> case do
        nil -> nil
        %{versions: versions} -> versions
      end

    {:reply, versions, state}
  end

  @impl GenServer
  def handle_call({:latest_for, module_name}, _from, state) do
    latest =
      state
      |> Enum.find(fn %{name: name} -> name == module_name end)
      |> case do
        nil -> nil
        %{latest: latest} -> latest
      end

    {:reply, latest, state}
  end

  @doc """
  Get the current in-process list of adaptors.
  This call will wait behind the `:continue` message when the process starts
  up, so it may take a while the first time it is called (and the list hasn't
  been fetched yet).
  """
  @spec all(server :: GenServer.server()) :: list()
  def all(server \\ __MODULE__) do
    GenServer.call(server, :all, @timeout)
  end

  @doc """
  Get a list of versions for a given module.
  """
  @spec versions_for(server :: GenServer.server(), module_name :: String.t()) ::
          list() | nil
  def versions_for(server \\ __MODULE__, module_name) do
    GenServer.call(server, {:versions_for, module_name}, @timeout)
  end

  @doc """
  Get a latest version for a given module.
  """
  @spec latest_for(server :: GenServer.server(), module_name :: String.t()) ::
          list() | nil
  def latest_for(server \\ __MODULE__, module_name) do
    GenServer.call(server, {:latest_for, module_name}, @timeout)
  end

  @doc """
  Fetch a list of packages for the @openfn organisation
  """
  @spec fetch() :: [map()]
  def fetch do
    start = DateTime.utc_now()
    Logger.debug("Fetching adaptors from NPM.")

    result =
      Npm.user_packages("openfn")
      |> Enum.map(fn {name, _} -> name end)
      |> Enum.filter(fn name ->
        Regex.match?(~r/@openfn\/language-\w+/, name)
      end)
      |> Enum.reject(fn name ->
        name in @excluded_adaptors
      end)
      |> Task.async_stream(
        &fetch_npm_details/1,
        ordered: false,
        max_concurrency: 10,
        timeout: @timeout
      )
      |> Stream.map(fn {:ok, detail} -> detail end)
      |> Enum.to_list()

    diff = DateTime.utc_now() |> DateTime.diff(start, :millisecond)
    Logger.debug(fn -> "Finished fetching adaptors in #{diff}ms." end)

    result
  end

  defp fetch_npm_details(package_name) do
    details = Npm.package_detail(package_name)

    %{
      name: details["name"],
      repo: details["repository"]["url"],
      latest: details["dist-tags"]["latest"],
      versions:
        Enum.map(details["versions"], fn {version, _detail} ->
          %{version: version}
        end)
    }
  end

  @doc """
  Destructures an NPM style package name into module name and version.

  **Example**

      iex> resolve_package_name("@openfn/language-salesforce@1.2.3")
      { "@openfn/language-salesforce", "1.2.3" }
      iex> resolve_package_name("@openfn/language-salesforce")
      { "@openfn/language-salesforce", nil }

  """
  @spec resolve_package_name(package_name :: nil) :: {nil, nil}
  def resolve_package_name(package_name) when is_nil(package_name),
    do: {nil, nil}

  @spec resolve_package_name(package_name :: String.t()) ::
          {binary | nil, binary | nil}
  def resolve_package_name(package_name) when is_binary(package_name) do
    ~r/(@?[\/\d\n\w-]+)(?:@([\d\.\w-]+))?$/
    |> Regex.run(package_name)
    |> case do
      [_, name, version] ->
        {name, version}

      [_, _name] ->
        {package_name, nil}

      _ ->
        {nil, nil}
    end
  end

  @doc """
  Same as `resolve_package_name/1` except will throw an exception if a package
  name cannot be matched.
  """
  @spec resolve_package_name!(package_name :: String.t()) ::
          {binary, binary | nil}
  def resolve_package_name!(package_name) when is_binary(package_name) do
    {package_name, version} = resolve_package_name(package_name)

    if is_nil(package_name) do
      raise ArgumentError, "Only npm style package names are currently supported"
    end

    {package_name, version}
  end

  def resolve_adaptor(adaptor) do
    __MODULE__.resolve_package_name(adaptor)
    |> case do
      {nil, nil} ->
        ""

      {adaptor_name, "latest"} ->
        "#{adaptor_name}@#{__MODULE__.latest_for(adaptor_name)}"

      _ ->
        adaptor
    end
  end
end
