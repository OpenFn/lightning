defmodule Lightning.Adaptors.CacheManager do
  @moduledoc """
  Supervisor that manages Cachex cache with appropriate warmers.

  This supervisor owns and manages the Cachex cache process, selecting
  appropriate warmers based on cache file existence:

  1. Cache file exists → CacheRestorer (required) + StrategyWarmer (optional)
  2. No cache file → StrategyWarmer (required)

  The supervisor leverages Cachex's built-in warmer system for clean
  cache management without complex coordination.
  """

  use Supervisor
  import Cachex.Spec
  require Logger

  @type config :: Lightning.Adaptors.API.config()

  @doc """
  Starts the CacheManager supervisor for the given adaptor configuration.

  Expected config keys:
  - :name - instance name
  - :cache - cachex cache name
  - :strategy - strategy module and config
  - :persist_path - optional path for persistence
  - :warm_interval - interval between cache warming cycles
  """
  @spec start_link(config :: config()) :: Supervisor.on_start()
  def start_link(config) do
    Supervisor.start_link(__MODULE__, config, name: via_name(config.name))
  end

  @doc """
  Child spec for use in supervision trees.
  """
  def child_spec(config) do
    %{
      id: {__MODULE__, config.name},
      start: {__MODULE__, :start_link, [config]},
      type: :supervisor
    }
  end

  @impl Supervisor
  def init(config) do
    warmers = determine_warmers(config)

    children = [
      {Cachex, [config.cache, [warmers: warmers]]}
    ]

    Logger.info("Cache manager initialized for #{config.name} with #{length(warmers)} warmers")
    
    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Determines which warmers to use based on cache file existence and configuration.
  """
  def determine_warmers(config) do
    if cache_file_exists?(config) do
      # Cache file exists: restore from file first, then optionally refresh
      [
        warmer(
          state: config,
          module: Lightning.Adaptors.CacheRestorer,
          required: true
        ),
        warmer(
          state: config,
          module: Lightning.Adaptors.Warmer,
          required: false,
          interval: Map.get(config, :warm_interval, :timer.minutes(5))
        )
      ]
    else
      # No cache file: must warm from strategy
      [
        warmer(
          state: config,
          module: Lightning.Adaptors.Warmer,
          required: true,
          interval: Map.get(config, :warm_interval, :timer.minutes(5))
        )
      ]
    end
  end

  # Private functions

  defp via_name(name) do
    {:via, Registry, {Lightning.Adaptors.Registry, {name, :cache_manager}}}
  end

  defp cache_file_exists?(config) do
    case config.persist_path do
      nil -> false
      path -> File.exists?(path)
    end
  end
end
