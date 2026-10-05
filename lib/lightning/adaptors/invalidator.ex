defmodule Lightning.Adaptors.Invalidator do
  @moduledoc """
  Subscribes to cluster adaptor-change broadcasts and evicts matching
  local Cachex entries, keeping each node coherent with Postgres.

  Subscribes to `opts[:source_topic]` on `Lightning.PubSub` at init. On
  `{:changed, name, source}` it deletes every cache key
  `Lightning.Adaptors.Store` writes for that name, plus the source-wide
  `:packages` and `:catalogue` keys, which any change invalidates.
  Dropping `:icon_bytes` is what lets a committed icon error clear. Only
  the row moving can resolve it, and the row moving always broadcasts.
  There is no source filtering. A broadcast for a source not active on
  this node deletes keys that do not exist, which is a no-op.
  """

  use GenServer

  @doc """
  Start the Invalidator linked to the calling process.

  Required opts:
    * `:name` - registered process name.
    * `:source_topic` - `Phoenix.PubSub` topic to subscribe to.
    * `:cache` - Cachex table atom, from `Lightning.Adaptors.Supervisor.cache_name/1`.
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
    Cachex.del(state.cache, {:icon_meta, name, source})
    Cachex.del(state.cache, {:icon_bytes, source, name, :square})
    Cachex.del(state.cache, {:icon_bytes, source, name, :rectangle})
    Cachex.del(state.cache, {:packages, source})
    Cachex.del(state.cache, {:catalogue, source})
    {:noreply, state}
  end
end
