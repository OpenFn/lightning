defmodule Lightning.AdaptorDataTest do
  use Lightning.DataCase, async: true

  alias Lightning.AdaptorData
  alias Lightning.AdaptorData.CacheEntry

  describe "put/4 and get/2" do
    test "inserts and retrieves a cache entry" do
      assert {:ok, entry} =
               AdaptorData.put("registry", "adaptors", ~s({"list":[]}))

      assert %CacheEntry{
               kind: "registry",
               key: "adaptors",
               data: ~s({"list":[]}),
               content_type: "application/json"
             } = entry

      assert {:ok, fetched} = AdaptorData.get("registry", "adaptors")
      assert fetched.id == entry.id
    end

    test "upserts on conflict, replacing data and content_type" do
      assert {:ok, original} =
               AdaptorData.put("schema", "http", "v1", "application/json")

      assert {:ok, updated} =
               AdaptorData.put("schema", "http", "v2", "text/plain")

      assert updated.id == original.id
      assert updated.data == "v2"
      assert updated.content_type == "text/plain"
    end

    test "returns error for missing entry" do
      assert {:error, :not_found} = AdaptorData.get("nope", "nope")
    end
  end

  describe "put_many/2" do
    test "bulk inserts and upserts entries" do
      entries = [
        %{key: "a", data: "data_a"},
        %{key: "b", data: "data_b", content_type: "image/png"}
      ]

      assert {2, _} = AdaptorData.put_many("icons", entries)

      all = AdaptorData.get_all("icons")
      assert length(all) == 2

      assert %CacheEntry{key: "a", data: "data_a"} =
               Enum.find(all, &(&1.key == "a"))

      assert %CacheEntry{key: "b", content_type: "image/png"} =
               Enum.find(all, &(&1.key == "b"))

      # Upsert overwrites existing entries
      assert {1, _} =
               AdaptorData.put_many("icons", [
                 %{key: "a", data: "data_a_v2"}
               ])

      assert {:ok, %CacheEntry{data: "data_a_v2"}} =
               AdaptorData.get("icons", "a")
    end
  end

  describe "get_all/1" do
    test "returns entries ordered by key and scoped to kind" do
      AdaptorData.put("reg", "z-adaptor", "z")
      AdaptorData.put("reg", "a-adaptor", "a")
      AdaptorData.put("other", "should-not-appear", "x")

      entries = AdaptorData.get_all("reg")
      assert length(entries) == 2
      assert [%{key: "a-adaptor"}, %{key: "z-adaptor"}] = entries
    end
  end

  describe "delete_kind/1" do
    test "removes all entries for a kind" do
      AdaptorData.put("temp", "one", "1")
      AdaptorData.put("temp", "two", "2")
      AdaptorData.put("keep", "three", "3")

      assert {2, _} = AdaptorData.delete_kind("temp")
      assert AdaptorData.get_all("temp") == []
      assert length(AdaptorData.get_all("keep")) == 1
    end
  end

  describe "delete/2" do
    test "deletes a specific entry and returns it" do
      AdaptorData.put("kind", "target", "data")
      AdaptorData.put("kind", "keep", "data")

      assert {:ok, %CacheEntry{key: "target"}} =
               AdaptorData.delete("kind", "target")

      assert {:error, :not_found} = AdaptorData.get("kind", "target")
      assert {:ok, _} = AdaptorData.get("kind", "keep")
    end

    test "returns error when entry does not exist" do
      assert {:error, :not_found} = AdaptorData.delete("nope", "nope")
    end
  end
end
