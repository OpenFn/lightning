defmodule Lightning.Adaptors.Invalidator do
  @moduledoc """
  Subscribes to cluster adaptor-change broadcasts and evicts matching
  local Cachex entries, keeping each node coherent with Postgres.

  Subscribes to `opts[:source_topic]` on `Lightning.PubSub` at init.
  On `{:changed, name, source}`, deletes the four per-adaptor cache keys
  written by `Lightning.Adaptors.Store`. No source filtering on the hot
  path — a broadcast for a source that isn't active on this node is a
  no-op because those keys simply don't exist in Cachex.
  """

  use GenServer

  @doc """
  Start the Invalidator linked to the calling process.

  Required opts:
    * `:name` — registered process name.
    * `:source_topic` — `Phoenix.PubSub` topic to subscribe to.
    * `:cache` — Cachex table atom (from `Lightning.Adaptors.Supervisor.cache_name/1`).
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    topic = Keyword.fetch!(opts, :source_topic)
    cache = Keyword.fetch!(opts, :cache)
    :ok = Phoenix.PubSub.subscribe(Lightning.PubSub, topic)
    {:ok, %{cache: cache}}
  end

  @impl true
  def handle_info({:changed, name, source}, state) do
    Cachex.del(state.cache, {:schema, name, source})
    Cachex.del(state.cache, {:versions, name, source})
    Cachex.del(state.cache, {:icon_meta, name, source})
    Cachex.del(state.cache, {:packages, source})
    {:noreply, state}
  end
end
