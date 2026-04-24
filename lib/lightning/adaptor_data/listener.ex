defmodule Lightning.AdaptorData.Listener do
  @moduledoc """
  GenServer that subscribes to PubSub for cache invalidation messages.

  When a node writes new data to the DB, it broadcasts
  `{:invalidate_cache, kinds, node()}`. All nodes (including the sender)
  clear those kinds from their ETS cache. The next read on any node will
  go to DB and repopulate ETS.
  """

  use GenServer
  require Logger

  def start_link(opts \\ []) do
    GenServer.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl GenServer
  def init(_opts) do
    Lightning.API.subscribe("adaptor:data")
    {:ok, %{}}
  end

  @impl GenServer
  def handle_info({:invalidate_cache, kinds, _origin_node}, state) do
    Logger.info("Invalidating adaptor cache for: #{inspect(kinds)}")

    Enum.each(kinds, &Lightning.AdaptorData.Cache.invalidate/1)

    {:noreply, state}
  end

  def handle_info(_msg, state), do: {:noreply, state}
end
