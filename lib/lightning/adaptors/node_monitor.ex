defmodule Lightning.Adaptors.NodeMonitor do
  @moduledoc """
  Partition-recovery companion to `Lightning.Adaptors.Invalidator`.

  On `:nodeup`, re-warms the Cachex table from Postgres so a reconnecting
  peer never serves stale data until the 24-hour TTL expires. Steady-state
  invalidation belongs to `Lightning.Adaptors.Invalidator`.

  `:nodedown` is a deliberate no-op. The worst case on a silent departure is
  one stale-URL redirect per client, backstopped by 302-on-stale-sha.
  """

  use GenServer

  alias Lightning.Adaptors.Store

  @doc """
  Start a NodeMonitor for the given supervisor instance.

  Required opts:
    * `:name` — registered GenServer name (§6.11 async-test rule).
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

  # Deliberate no-op: nodedown does not trigger a re-warm. The 24h Cachex TTL
  # backstops any staleness; 302-on-stale-sha handles already-issued URLs.
  def handle_info({:nodedown, _node, _info}, state) do
    {:noreply, state}
  end
end
