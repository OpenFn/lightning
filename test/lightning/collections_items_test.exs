defmodule Lightning.CollectionsItemsTest do
  use Lightning.DataCase, async: true

  import Lightning.QueryCountHelpers

  alias Lightning.Collections
  alias Lightning.Collections.Item

  describe "get/2" do
    test "returns the entry of the given collection, or nil" do
      %{key: key, value: value, collection: collection} =
        insert(:collection_item) |> Repo.preload(:collection)

      assert %Item{key: ^key, value: ^value} = Collections.get(collection, key)
      refute Collections.get(collection, "nonexistent")
      refute Collections.get(%{id: Ecto.UUID.generate()}, key)
    end
  end

  describe "get_all/3" do
    test "returns all items for the given collection sorted by inserted_at" do
      collection = insert(:collection)

      items =
        1..11
        |> Enum.map(fn _i ->
          insert(:collection_item,
            key: "rkey#{:rand.uniform()}",
            collection: collection
          )
        end)

      get_items =
        Collections.get_all(collection, limit: 50)
        |> Repo.preload(collection: :project)

      assert List.last(get_items) ==
               Enum.sort_by(items, & &1.inserted_at) |> List.last()

      assert MapSet.new(get_items) == MapSet.new(items)
    end

    test "returns the items after a cursor up to a limited amount" do
      collection = insert(:collection)

      items =
        Enum.map(1..30, fn _i ->
          insert(:collection_item,
            key: "rkey#{:rand.uniform()}",
            collection: collection
          )
        end)

      %{id: cursor} = Enum.at(items, 4)

      assert Collections.get_all(collection, cursor: cursor, limit: 50)
             |> Enum.count() == 30 - (4 + 1)

      assert Collections.get_all(collection, cursor: cursor, limit: 10)
             |> Enum.count() == 10
    end

    test "returns an empty list for an empty or missing collection" do
      assert [] = Collections.get_all(insert(:collection), limit: 50)

      insert(:collection_item, key: "existing_key")

      assert [] = Collections.get_all(%{id: Ecto.UUID.generate()}, limit: 50)
    end
  end

  describe "stream_all/3" do
    setup do
      collection = insert(:collection)
      insert_list(20, :collection_item, collection: collection)
      %{collection: collection}
    end

    test "reads every item a page at a time, stopping at the short page",
         %{collection: collection} do
      Mox.stub(Lightning.MockConfig, :collections_stream_page_size, fn -> 15 end)

      {items, queries} =
        count_queries(
          fn -> collection |> Collections.stream_all(%{}) |> Enum.to_list() end,
          "collection_items"
        )

      assert Enum.map(items, & &1.id) ==
               Enum.map(Collections.get_all(collection, limit: 50), & &1.id)

      assert queries == 2
    end

    test "reads no more than :limit asks for", %{collection: collection} do
      {items, queries} =
        count_queries(
          fn ->
            collection |> Collections.stream_all(%{limit: 5}) |> Enum.to_list()
          end,
          "collection_items"
        )

      assert Enum.map(items, & &1.id) ==
               Enum.map(Collections.get_all(collection, limit: 5), & &1.id)

      assert queries == 1
    end
  end

  describe "get_all/3 with key pattern" do
    test "returns item with exact match" do
      collection = insert(:collection)
      _itemA = insert(:collection_item, key: "keyA", collection: collection)
      itemB = insert(:collection_item, key: "keyB", collection: collection)

      assert [itemB] ==
               Collections.get_all(collection, %{limit: 50}, "keyB*")
               |> Repo.preload(collection: :project)
    end

    test "returns matching items for the given collection sorted by id" do
      collection = insert(:collection)

      insert(:collection_item, key: "rkeynomatch", collection: collection)

      items =
        Enum.map(1..11, fn _i ->
          insert(:collection_item,
            key: "rkeymatch#{:rand.uniform()}",
            collection: collection
          )
          |> item_reload()
        end)

      get_items = Collections.get_all(collection, %{limit: 50}, "rkeymatch*")

      assert List.last(get_items) == Enum.max_by(items, & &1.id)

      assert MapSet.new(get_items) == MapSet.new(items)
    end

    test "returns matching items after a cursor up to a limited amount" do
      collection = insert(:collection)

      items =
        Enum.map(1..30, fn _i ->
          insert(:collection_item,
            key: "rkeyA#{:rand.uniform()}",
            collection: collection
          )
        end)

      %{id: cursor} = Enum.at(items, 9)

      insert(:collection_item, key: "rkeyB", collection: collection)

      assert Collections.get_all(
               collection,
               %{cursor: cursor, limit: 50},
               "rkeyA*"
             )
             |> Enum.count() == 30 - (9 + 1)

      assert Collections.get_all(
               collection,
               %{cursor: cursor, limit: 16},
               "rkeyA*"
             )
             |> Enum.count() == 16
    end

    test "returns an empty list for an empty or missing collection" do
      assert [] =
               Collections.get_all(insert(:collection), %{limit: 50}, "any-key")

      insert(:collection_item, key: "existing_key")

      assert [] =
               Collections.get_all(
                 %{id: Ecto.UUID.generate()},
                 %{limit: 50},
                 "existing_key"
               )
    end

    test "returns item escaping the %" do
      collection = insert(:collection)

      item =
        insert(:collection_item, key: "keyA%", collection: collection)
        |> item_reload()

      assert [item] == Collections.get_all(collection, %{limit: 50}, "keyA%*")

      insert(:collection_item, key: "keyBC", collection: collection)

      assert [] = Collections.get_all(collection, %{limit: 50}, "keyB%")
    end

    test "returns item escaping the \\" do
      collection = insert(:collection)

      item =
        insert(:collection_item, key: "keyA\\", collection: collection)
        |> item_reload()

      assert [item] == Collections.get_all(collection, %{limit: 50}, "keyA\\*")
    end
  end

  defp item_reload(item) do
    # composite primary
    Repo.get_by(Item, id: item.id, collection_id: item.collection_id)
  end
end
