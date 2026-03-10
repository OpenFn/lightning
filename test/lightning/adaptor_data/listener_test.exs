defmodule Lightning.AdaptorData.ListenerTest do
  use Lightning.DataCase, async: true

  alias Lightning.AdaptorData
  alias Lightning.AdaptorData.Cache
  alias Lightning.AdaptorData.Listener

  defp unique_kind, do: "listener_kind_#{System.unique_integer([:positive])}"

  describe "handle_info/2 {:invalidate_cache, ...}" do
    test "invalidates ETS cache for each kind when receiving PubSub message" do
      kind1 = unique_kind()
      kind2 = unique_kind()

      # Put data in DB and populate ETS via Cache.get
      {:ok, _} = AdaptorData.put(kind1, "k", "original1")
      {:ok, _} = AdaptorData.put(kind2, "k", "original2")
      Cache.get(kind1, "k")
      Cache.get(kind2, "k")

      # Simulate the PubSub message the Listener would receive
      send(Listener, {:invalidate_cache, [kind1, kind2], node()})

      # Give the GenServer time to process
      # We verify by checking ETS is empty for those keys
      :sys.get_state(Listener)

      # Update DB so we can verify reads go to DB
      {:ok, _} = AdaptorData.put(kind1, "k", "updated1")
      {:ok, _} = AdaptorData.put(kind2, "k", "updated2")

      assert %{data: "updated1"} = Cache.get(kind1, "k")
      assert %{data: "updated2"} = Cache.get(kind2, "k")
    end
  end

  describe "integration with PubSub broadcast" do
    test "end-to-end: broadcast triggers listener to invalidate cache" do
      kind = unique_kind()

      {:ok, _} = AdaptorData.put(kind, "key", "before")
      Cache.get(kind, "key")

      # Update DB
      {:ok, _} = AdaptorData.put(kind, "key", "after")

      # Broadcast invalidation (Listener is subscribed)
      Cache.broadcast_invalidation([kind])

      # Wait for Listener to process
      :sys.get_state(Listener)

      # Cache should now read from DB
      assert %{data: "after"} = Cache.get(kind, "key")
    end
  end
end
