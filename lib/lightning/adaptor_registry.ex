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
  AdaptorRegistry.all()
  ```

  **Caching**

  By default the results are cached to disk, and will be reused every start.

  In order to disable caching pass see: `start_link/1`.

  The process uses `:continue` to return before the adaptors have been queried.
  This does mean that the first call to the process will be delayed until
  the `handle_continue/2` has finished.
  """

  use GenServer

  @excluded_adaptors ["@openfn/language-devtools", "@openfn/language-template"]

  defmodule Npm do
    @moduledoc """
    NPM API functions
    """
    use HTTPoison.Base

    def process_request_url(url) do
      "https://registry.npmjs.org" <> url
    end

    def process_response_body(body) do
      body
      |> Jason.decode!()
    end

    @doc """
    Retrieve all packages for a given user or organization
    """
    @spec user_packages(user :: String.t()) :: [map()]
    def user_packages(user) do
      get!("/-/user/#{user}/package", [], hackney: [pool: :default]).body
    end

    @doc """
    Retrieve all details for an NPM package
    """
    @spec package_detail(package_name :: String.t()) :: map()
    def package_detail(package_name) do
      get!("/#{package_name}", [], hackney: [pool: :default]).body
    end
  end

  @impl GenServer
  def init(opts) do
    {:ok, [], {:continue, opts}}
  end

  @impl GenServer
  def handle_continue(opts, _state) do
    if opts[:use_cache] do
      read_from_cache()
      |> case do
        nil ->
          {:noreply, fetch() |> write_to_cache()}

        adaptors ->
          {:noreply, adaptors}
      end
    else
      {:noreply, fetch()}
    end
  end

  defp write_to_cache(adaptors) do
    File.mkdir("tmp")
    cache_file = File.open!("tmp/adaptor_registry_cache.json", [:write])
    IO.binwrite(cache_file, Jason.encode_to_iodata!(adaptors))
    File.close(cache_file)

    adaptors
  end

  defp read_from_cache() do
    File.read("tmp/adaptor_registry_cache.json")
    |> case do
      {:ok, file} -> Jason.decode!(file, keys: :atoms)
      {:error, _} -> nil
    end
  end

  @doc """
  Starts the AdaptorRegistry

  **Options**

  - `:use_cache` (defaults to true) - stores the last set of results on disk
    and uses the cached file for every subsequent start.
  """
  @spec start_link(opts :: [use_cache: boolean()]) :: {:error, any} | {:ok, pid}
  def start_link(opts \\ [use_cache: true]) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def handle_call(:all, _from, state) do
    {:reply, state, state}
  end

  @doc """
  Get the current in-process list of adaptors.
  This call will wait behind the `:continue` message when the process starts
  up, so it may take a while the first time it is called (and the list hasn't
  been fetched yet).
  """
  def all() do
    GenServer.call(__MODULE__, :all, 30000)
  end

  def fetch() do
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
      max_concurrency: 5,
      timeout: 30000
    )
    |> Stream.map(fn {:ok, detail} -> detail end)
    |> Enum.to_list()
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
end
