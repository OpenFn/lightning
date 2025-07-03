defmodule Lightning.Adaptors do
  @moduledoc """
  Adaptor registry

  This module provides a strategy-based adaptor registry that can fetch adaptors
  from different sources (NPM, local repositories, etc.) and cache them efficiently.

  ## Usage

  Start the Adaptors process in your supervision tree:

      children = [
        {Lightning.Adaptors, [
          strategy: {Lightning.Adaptors.NPMStrategy, []},
          persist_path: "/tmp/adaptors_cache"
        ]}
      ]

  Then call functions without passing config:

      Lightning.Adaptors.all()
      Lightning.Adaptors.versions_for("@openfn/language-http")

  You can also create facade modules for different configurations:

      defmodule MyApp.Adaptors do
        use Lightning.Adaptors, otp_app: :my_app
      end

  And configure them in your config files:

      config :my_app, MyApp.Adaptors,
        strategy: {Lightning.Adaptors.NPMStrategy, []},
        persist_path: "/tmp/my_app_adaptors"

  ## Caching Strategy

  The registry uses a two-level caching approach:
  1. Individual adaptors are cached by their name for efficient lookup
  2. A list of all adaptor names is cached under the `"adaptors"` key

  This allows both fast listing (for AdaptorPicker) and fast individual lookups
  (for versions_for/latest_for functions).

  ## Persistence

  The cache can be persisted to disk and restored across application restarts
  using the `:persist_path` configuration option. When provided, the cache will
  be automatically restored on first access and saved after updates.
  """

  require Logger

  @doc """
  Creates a facade for `Lightning.Adaptors` functions and automates fetching configuration
  from the application environment.

  Facade modules support configuration via the application environment under an OTP application
  key. For example, the facade:

      defmodule MyApp.Adaptors do
        use Lightning.Adaptors, otp_app: :my_app
      end

  Could be configured with:

      config :my_app, MyApp.Adaptors,
        strategy: {Lightning.Adaptors.NPMStrategy, []},
        persist_path: "/tmp/my_app_adaptors"

  Then you can include `MyApp.Adaptors` in your application's supervision tree without passing extra
  options:

      defmodule MyApp.Application do
        use Application

        def start(_type, _args) do
          children = [
            MyApp.Repo,
            MyApp.Adaptors
          ]

          opts = [strategy: :one_for_one, name: MyApp.Supervisor]
          Supervisor.start_link(children, opts)
        end
      end

  ### Calling Functions

  Facade modules allow you to call `Lightning.Adaptors` functions on instances with custom names
  without passing a name as the first argument.

  For example, rather than calling `Lightning.Adaptors.all/1` you'd call `MyAdaptors.all/0`:

      MyAdaptors.all()

  ### Merging Configuration

  All configuration can be provided through the `use` macro or application config, and options
  from the application supersede those passed through `use`. Configuration is prioritized in
  order:

  1. Options passed through `use`
  2. Options pulled from the OTP app via `Application.get_env/3`
  3. Options passed through a child spec in the supervisor
  """
  defmacro __using__(opts \\ []) do
    {otp_app, child_opts} = Keyword.pop!(opts, :otp_app)

    quote do
      def child_spec(opts) do
        unquote(child_opts)
        |> Keyword.merge(Application.get_env(unquote(otp_app), __MODULE__, []))
        |> Keyword.merge(opts)
        |> Keyword.put(:name, __MODULE__)
        |> Lightning.Adaptors.Supervisor.child_spec()
      end

      def config do
        Lightning.Adaptors.config(__MODULE__)
      end

      def all do
        Lightning.Adaptors.all(__MODULE__)
      end

      def versions_for(module_name) do
        Lightning.Adaptors.versions_for(__MODULE__, module_name)
      end

      def latest_for(module_name) do
        Lightning.Adaptors.latest_for(__MODULE__, module_name)
      end

      def fetch_configuration_schema(module_name) do
        Lightning.Adaptors.fetch_configuration_schema(__MODULE__, module_name)
      end

      def save_cache do
        Lightning.Adaptors.save_cache(__MODULE__)
      end

      def restore_cache do
        Lightning.Adaptors.restore_cache(__MODULE__)
      end

      def clear_persisted_cache do
        Lightning.Adaptors.clear_persisted_cache(__MODULE__)
      end

      defoverridable config: 0,
                     all: 0,
                     versions_for: 1,
                     latest_for: 1,
                     save_cache: 0,
                     restore_cache: 0,
                     clear_persisted_cache: 0
    end
  end

  @typedoc """
  The name of an Adaptors instance. This is used to identify instances in the
  internal registry for configuration lookup.
  """
  @type name :: term()

  @type config :: %{
          strategy: {module(), term()},
          cache: Cachex.t(),
          persist_path: String.t() | nil,
          offline_mode: boolean(),
          warm_interval: pos_integer()
        }

  @type option ::
          {:name, name()}
          | {:strategy, {module(), term()} | module()}
          | {:persist_path, String.t() | nil}
          | {:offline_mode, boolean()}
          | {:warm_interval, pos_integer()}

  @doc """
  Returns the child spec for starting Adaptors in a supervision tree.
  """
  @spec child_spec([option()]) :: Supervisor.child_spec()
  def child_spec(opts) do
    Lightning.Adaptors.Supervisor.child_spec(opts)
  end


  @doc """
  Start an Adaptors supervision tree with the given options.

  ## Options

  * `:name` - used for process registration, defaults to `Lightning.Adaptors`
  * `:strategy` - the strategy module and config for fetching packages
  * `:persist_path` - optional path for cache persistence

  ## Example

      {:ok, pid} = Lightning.Adaptors.start_link([
        strategy: {Lightning.Adaptors.NPM, []},
        persist_path: "/tmp/adaptors_cache"
      ])
  """
  @spec start_link([option()]) :: Supervisor.on_start()
  def start_link(opts) when is_list(opts) do
    Lightning.Adaptors.Supervisor.start_link(opts)
  end

  @doc """
  Retrieve the configuration for a named Adaptors instance.

  ## Example

      config = Lightning.Adaptors.config()
      config = Lightning.Adaptors.config(MyAdaptors)
  """
  @spec config(name()) :: config()
  def config(name \\ __MODULE__), do: Lightning.Adaptors.Registry.config(name)

  @callback all(name()) :: {:ok, [String.t()]} | {:error, term()}
  @callback versions_for(name(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback latest_for(name(), String.t()) :: {:ok, map()} | {:error, term()}
  @callback fetch_configuration_schema(name(), String.t()) ::
              {:ok, map()} | {:error, term()}
  @callback save_cache(name()) :: :ok | {:error, term()}
  @callback restore_cache(name()) :: :ok | {:error, term()}
  @callback clear_persisted_cache(name()) :: :ok | {:error, term()}

  @doc """
  Returns a list of all adaptor names.

  Caches both the list of names and individual adaptor details for efficient lookup.
  On first access, attempts to restore cache from disk if persist_path is configured.

  ## Example

      # Using default instance
      adaptors = Lightning.Adaptors.all()

      # Using named instance
      adaptors = Lightning.Adaptors.all(MyAdaptors)
  """
  def all(name \\ __MODULE__) do
    Lightning.Adaptors.API.all(name)
  end

  @doc """
  Returns the list of versions for a specific adaptor.

  If the adaptor is not cached, will populate the cache by calling all/1 first.
  Returns nil if the adaptor is not found.

  ## Example

      # Using default instance
      versions = Lightning.Adaptors.versions_for("@openfn/language-http")

      # Using named instance
      versions = Lightning.Adaptors.versions_for(MyAdaptors, "@openfn/language-http")
  """
  def versions_for(name, module_name \\ nil)

  def versions_for(name, nil) do
    # Single argument case - use default instance
    Lightning.Adaptors.API.versions_for(__MODULE__, name)
  end

  def versions_for(name, module_name) do
    # Two argument case - named instance
    Lightning.Adaptors.API.versions_for(name, module_name)
  end

  @doc """
  Returns the latest version for a specific adaptor.

  If the adaptor is not cached, will populate the cache by calling all/1 first.
  Returns nil if the adaptor is not found.

  ## Example

      # Using default instance
      latest = Lightning.Adaptors.latest_for("@openfn/language-http")

      # Using named instance
      latest = Lightning.Adaptors.latest_for(MyAdaptors, "@openfn/language-http")
  """
  def latest_for(name, module_name \\ nil)

  def latest_for(name, nil) do
    # Single argument case - use default instance
    Lightning.Adaptors.API.latest_for(__MODULE__, name)
  end

  def latest_for(name, module_name) do
    # Two argument case - named instance
    Lightning.Adaptors.API.latest_for(name, module_name)
  end

  def fetch_configuration_schema(name, module_name) do
    Lightning.Adaptors.API.fetch_configuration_schema(name, module_name)
  end

  @doc """
  Saves the cache to disk if persist_path is configured.

  Returns :ok if successful or if no persist_path is configured,
  {:error, reason} if saving fails.
  """
  def save_cache(name \\ __MODULE__) do
    Lightning.Adaptors.API.save_cache(name)
  end

  @doc """
  Restores the cache from disk if persist_path is configured.

  Returns :ok if successful or if no persist_path is configured,
  {:error, reason} if restoration fails.
  """
  def restore_cache(name \\ __MODULE__) do
    Lightning.Adaptors.API.restore_cache(name)
  end

  @doc """
  Clears the persisted cache file if it exists.

  Returns :ok if successful or if no persist_path is configured,
  {:error, reason} if deletion fails.
  """
  def clear_persisted_cache(name \\ __MODULE__) do
    Lightning.Adaptors.API.clear_persisted_cache(name)
  end

  # defp restore_cache_if_needed(config) do
  #   # Only restore if cache appears to be empty (no "adaptors" key)
  #   case Cachex.get(config[:cache], "adaptors") do
  #     {:ok, nil} ->
  #       Repository.restore_cache(config)

  #     _ ->
  #       :ok
  #   end
  # end

  def packages_filter(name) do
    name not in [
      "@openfn/language-devtools",
      "@openfn/language-template",
      "@openfn/language-fhir-jembi",
      "@openfn/language-collections"
    ] &&
      Regex.match?(~r/@openfn\/language-\w+/, name)
  end

end
