defmodule Lightning.AdaptorData.CacheTest do
  use Lightning.DataCase, async: true

  alias Lightning.AdaptorData
  alias Lightning.AdaptorData.Cache

  # Each test gets its own kind to avoid cross-test ETS collisions
  defp unique_kind, do: "test_kind_#{System.unique_integer([:positive])}"

  setup do
    # Ensure ETS is clean for our test kinds
    :ok
  end

  describe "get/2" do
    test "returns nil when entry does not exist in DB or ETS" do
      kind = unique_kind()
      assert Cache.get(kind, "missing") == nil
    end

    test "falls back to DB on cache miss and populates cache" do
      kind = unique_kind()
      {:ok, _entry} = AdaptorData.put(kind, "key1", "some data", "text/plain")

      # First call: cache miss, DB hit, populates cache
      result = Cache.get(kind, "key1")
      assert %{data: "some data", content_type: "text/plain"} = result

      # Second call: cache hit (verify by reading Cachex directly)
      assert Cachex.get!(:adaptor_data, {kind, "key1"}) == result
    end

    test "returns cached value on subsequent calls" do
      kind = unique_kind()
      {:ok, _entry} = AdaptorData.put(kind, "key2", ~s({"a":1}))

      # Populate ETS
      first = Cache.get(kind, "key2")
      assert %{data: ~s({"a":1}), content_type: "application/json"} = first

      # Update DB directly (bypassing cache)
      {:ok, _entry} = AdaptorData.put(kind, "key2", ~s({"a":2}))

      # ETS still returns stale value (proving it reads from ETS)
      assert Cache.get(kind, "key2") == first
    end
  end

  describe "get_all/1" do
    test "returns empty list when no entries exist" do
      kind = unique_kind()
      assert Cache.get_all(kind) == []
    end

    test "falls back to DB and populates cache with mapped entries" do
      kind = unique_kind()
      {:ok, _} = AdaptorData.put(kind, "a", "data_a", "text/plain")
      {:ok, _} = AdaptorData.put(kind, "b", "data_b", "application/json")

      result = Cache.get_all(kind)

      assert [
               %{key: "a", data: "data_a", content_type: "text/plain"},
               %{key: "b", data: "data_b", content_type: "application/json"}
             ] = result

      # Verify Cachex was populated with the :__all__ key
      assert Cachex.get!(:adaptor_data, {kind, :__all__}) == result
    end

    test "returns cached list on subsequent calls" do
      kind = unique_kind()
      {:ok, _} = AdaptorData.put(kind, "x", "data_x")

      first = Cache.get_all(kind)
      assert length(first) == 1

      # Add another entry to DB (bypassing cache)
      {:ok, _} = AdaptorData.put(kind, "y", "data_y")

      # ETS still returns the original list
      assert Cache.get_all(kind) == first
    end
  end

  describe "invalidate/1" do
    test "clears ETS entries for a kind so next read goes to DB" do
      kind = unique_kind()
      {:ok, _} = AdaptorData.put(kind, "k1", "original")

      # Populate ETS via read
      assert %{data: "original"} = Cache.get(kind, "k1")
      assert [%{key: "k1"}] = Cache.get_all(kind)

      # Update DB
      {:ok, _} = AdaptorData.put(kind, "k1", "updated")

      # Invalidate
      assert :ok = Cache.invalidate(kind)

      # Next read goes to DB and gets updated value
      assert %{data: "updated"} = Cache.get(kind, "k1")
    end

    test "does not affect entries of other kinds" do
      kind1 = unique_kind()
      kind2 = unique_kind()

      {:ok, _} = AdaptorData.put(kind1, "k", "data1")
      {:ok, _} = AdaptorData.put(kind2, "k", "data2")

      # Populate both in ETS
      Cache.get(kind1, "k")
      Cache.get(kind2, "k")

      # Invalidate only kind1
      Cache.invalidate(kind1)

      # kind2 still cached (stale check: update DB, ETS should still have old)
      {:ok, _} = AdaptorData.put(kind2, "k", "data2_updated")
      assert %{data: "data2"} = Cache.get(kind2, "k")
    end
  end

  describe "invalidate_all/0" do
    test "clears all ETS entries" do
      kind1 = unique_kind()
      kind2 = unique_kind()

      {:ok, _} = AdaptorData.put(kind1, "k", "d1")
      {:ok, _} = AdaptorData.put(kind2, "k", "d2")

      Cache.get(kind1, "k")
      Cache.get(kind2, "k")

      assert :ok = Cache.invalidate_all()

      # Update DB so we can verify reads go to DB
      {:ok, _} = AdaptorData.put(kind1, "k", "d1_new")
      {:ok, _} = AdaptorData.put(kind2, "k", "d2_new")

      assert %{data: "d1_new"} = Cache.get(kind1, "k")
      assert %{data: "d2_new"} = Cache.get(kind2, "k")
    end
  end

  describe "broadcast_invalidation/1" do
    test "broadcasts invalidation message via PubSub" do
      Lightning.API.subscribe("adaptor:data")

      Cache.broadcast_invalidation(["registry", "schema"])

      assert_receive {:invalidate_cache, ["registry", "schema"], _node}
    end
  end
end
