defmodule Lightning.Adaptors.Supervisor do
  @moduledoc """
  Supervisor for Lightning.Adaptors instances.

  This module handles the supervision tree setup for the Adaptors system.
  The CacheManager child manages its own Cachex cache internally.
  """

  use Supervisor
  require Logger

  @typedoc """
  Configuration for the Adaptors supervisor.
  """
  @type config :: %{
          name: Lightning.Adaptors.API.name(),
          cache: atom(),
          strategy: {module(), term()},
          persist_path: String.t() | nil,
          warm_interval: pos_integer()
        }

  @doc """
  Returns the child spec for starting the Adaptors supervisor.
  """
  @spec child_spec([Lightning.Adaptors.API.option()]) :: Supervisor.child_spec()
  def child_spec(opts) do
    opts
    |> super()
    |> Supervisor.child_spec(id: Keyword.get(opts, :name, Lightning.Adaptors))
  end

  @impl Supervisor
  def init(config) do
    children = [
      # CacheManager now owns and manages Cachex internally
      {Lightning.Adaptors.CacheManager, config}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Start an Adaptors supervision tree with the given options.

  ## Options

  * `:name` - used for process registration, defaults to `Lightning.Adaptors`
  * `:strategy` - the strategy module and config for fetching packages
  * `:persist_path` - optional path for cache persistence

  ## Example

      {:ok, pid} = Lightning.Adaptors.Supervisor.start_link([
        strategy: {Lightning.Adaptors.NPM, []},
        persist_path: "/tmp/adaptors_cache"
      ])
  """
  @spec start_link([Lightning.Adaptors.API.option()]) :: Supervisor.on_start()
  def start_link(opts) when is_list(opts) do
    name = Keyword.get(opts, :name, Lightning.Adaptors)
    cache_name = :"adaptors_cache_#{name}"

    config = %{
      name: name,
      cache: cache_name,
      strategy: Keyword.get(opts, :strategy, nil),
      persist_path: Keyword.get(opts, :persist_path),
      warm_interval:
        Keyword.get(
          opts,
          :warm_interval,
          Application.get_env(
            :lightning,
            :adaptor_warm_interval,
            :timer.minutes(5)
          )
        )
    }

    Supervisor.start_link(__MODULE__, config,
      name: Lightning.Adaptors.Registry.via(name, nil, config)
    )
  end
end
