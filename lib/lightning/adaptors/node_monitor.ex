defmodule Lightning.Adaptors.NodeMonitor do
  @moduledoc """
  Partition-recovery companion to `Lightning.Adaptors.Invalidator`.

  Cache entries have no TTL, so a node that misses a `:changed` broadcast
  while partitioned would otherwise serve it forever. On `:nodeup`,
  re-warms the Cachex table from Postgres to close that gap. Steady-state
  invalidation belongs to `Lightning.Adaptors.Invalidator`.

  `:nodedown` is a deliberate no-op: there's nothing to invalidate on this
  end when the connection drops. The worst case while partitioned is a
  stale icon URL, which `LightningWeb.AdaptorIconController`'s
  302-on-stale-sha handles regardless of which node serves the request.
  """

  use GenServer

  alias Lightning.Adaptors.Store

  @doc """
  Start a NodeMonitor for the given supervisor instance.

  Required opts:
    * `:name` — registered GenServer name.
    * `:sup` — supervisor instance name, forwarded to `Store.warm_from_repo/1`.
  """
  @spec start_link(keyword()) :: GenServer.on_start()
  def start_link(opts) do
    name = Keyword.fetch!(opts, :name)
    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    sup = Keyword.fetch!(opts, :sup)
    :net_kernel.monitor_nodes(true, node_type: :visible)
    {:ok, %{sup: sup}}
  end

  @impl true
  def handle_info({:nodeup, _node, _info}, state) do
    Store.warm_from_repo(state.sup)
    {:noreply, state}
  end

  # Deliberate no-op: nodedown does not trigger a re-warm. 302-on-stale-sha
  # handles already-issued icon URLs; other reads stay stale until nodeup.
  def handle_info({:nodedown, _node, _info}, state) do
    {:noreply, state}
  end
end
