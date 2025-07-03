defmodule Lightning.Adaptors.Service do
  @moduledoc """
  Service module for creating Lightning.Adaptors facade modules.
  
  This module provides the `__using__` macro that allows creating facade modules
  for Lightning.Adaptors functionality with custom configuration.
  """

  @doc """
  Creates a facade for `Lightning.Adaptors` functions and automates fetching configuration
  from the application environment.

  Facade modules support configuration via the application environment under an OTP application
  key. For example, the facade:

      defmodule MyApp.Adaptors do
        use Lightning.Adaptors.Service, otp_app: :my_app
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
      @behaviour Lightning.Adaptors.Service

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
        Lightning.Adaptors.API.all(__MODULE__)
      end

      def versions_for(module_name) do
        Lightning.Adaptors.API.versions_for(__MODULE__, module_name)
      end

      def latest_for(module_name) do
        Lightning.Adaptors.API.latest_for(__MODULE__, module_name)
      end

      def fetch_configuration_schema(module_name) do
        Lightning.Adaptors.API.fetch_configuration_schema(__MODULE__, module_name)
      end

      def save_cache do
        Lightning.Adaptors.API.save_cache(__MODULE__)
      end

      def restore_cache do
        Lightning.Adaptors.API.restore_cache(__MODULE__)
      end

      def clear_persisted_cache do
        Lightning.Adaptors.API.clear_persisted_cache(__MODULE__)
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

  @doc """
  Behaviour for Lightning.Adaptors facade modules.
  """
  @callback config() :: Lightning.Adaptors.config()
  @callback all() :: {:ok, [String.t()]} | {:error, term()}
  @callback versions_for(String.t()) :: {:ok, map()} | {:error, term()}
  @callback latest_for(String.t()) :: {:ok, map()} | {:error, term()}
  @callback fetch_configuration_schema(String.t()) :: {:ok, map()} | {:error, term()}
  @callback save_cache() :: :ok | {:error, term()}
  @callback restore_cache() :: :ok | {:error, term()}
  @callback clear_persisted_cache() :: :ok | {:error, term()}
end