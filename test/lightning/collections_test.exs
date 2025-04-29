defmodule Lightning.CollectionsTest do
  use Lightning.DataCase, async: true

  alias Lightning.Collections
  alias Lightning.Collections.Collection
  alias Lightning.Collections.Item

  describe "get_collection/1" do
    test "get a collection" do
      %{id: collection_id, name: collection_name} = insert(:collection)

      assert {:ok, %Collection{id: ^collection_id}} =
               Collections.get_collection(collection_name)
    end

    test "returns an error when the collection does not exist" do
      assert {:error, :not_found} =
               Collections.get_collection("nonexistent")
    end
  end

  describe "create_collection/2" do
    test "creates a new collection" do
      %{id: project_id} = insert(:project)
      name = "col1_project1"

      assert {:ok, %Collection{project_id: ^project_id, name: ^name}} =
               Collections.create_collection(%{
                 "project_id" => project_id,
                 "name" => name
               })
    end

    test "returns an error when collection name is taken" do
      %{id: project_id1} = insert(:project)
      name = "col1_project1"

      assert {:ok, %Collection{project_id: ^project_id1, name: ^name}} =
               Collections.create_collection(%{
                 "project_id" => project_id1,
                 "name" => name
               })

      assert {:error,
              %{
                errors: [
                  name:
                    {"A collection with this name already exists",
                     [
                       constraint: :unique,
                       constraint_name: "collections_name_index"
                     ]}
                ]
              }} =
               Collections.create_collection(%{
                 "project_id" => project_id1,
                 "name" => name
               })
    end

    test "returns an error when limit is exceeded" do
      %{id: project_id1} = insert(:project)
      %{id: project_id2} = insert(:project)

      assert {:ok, %Collection{project_id: ^project_id1, name: "col1"}} =
               Collections.create_collection(%{
                 "project_id" => project_id1,
                 "name" => "col1"
               })

      message = %Lightning.Extensions.Message{text: "some error"}

      Mox.stub(
        Lightning.Extensions.MockCollectionHook,
        :handle_create,
        fn %{"project_id" => _project_id} ->
          {:error, :exceeds_limit, message}
        end
      )

      assert {:error, :exceeds_limit, ^message} =
               Collections.create_collection(%{
                 "project_id" => project_id2,
                 "name" => "col2"
               })
    end
  end

  describe "delete_collection/1" do
    test "deletes a collection" do
      %{id: collection_id} = insert(:collection)

      assert {:ok, %Collection{id: ^collection_id}} =
               Collections.delete_collection(collection_id)
    end

    test "returns an error when collection does not exist" do
      assert {:error, :not_found} =
               Collections.delete_collection(Ecto.UUID.generate())
    end
  end

  describe "get/2" do
    test "returns an entry for the given collection" do
      %{key: key, value: value, collection: collection} =
        insert(:collection_item) |> Repo.preload(:collection)

      assert %Item{key: ^key, value: ^value} = Collections.get(collection, key)
    end

    test "returns nil if the item key does not exist" do
      collection = insert(:collection)

      refute Collections.get(collection, "nonexistent")
    end

    test "returns nil if the collection does not exist" do
      insert(:collection_item, key: "existing_key")

      refute Collections.get(%{id: Ecto.UUID.generate()}, "existing_key")
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

    test "returns empty list when collection is empty" do
      collection = insert(:collection)

      assert [] = Collections.get_all(collection, limit: 50)
    end

    test "returns empty list when the collection doesn't exist" do
      insert(:collection_item, key: "existing_key")

      assert [] = Collections.get_all(%{id: Ecto.UUID.generate()}, limit: 50)
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

    test "returns matching items for the given collection sorted by inserted_at" do
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

      assert List.last(get_items) ==
               Enum.sort_by(items, & &1.inserted_at) |> List.last()

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

    test "returns empty list when collection is empty" do
      collection = insert(:collection)

      assert [] = Collections.get_all(collection, %{limit: 50}, "any-key")
    end

    test "returns empty list when the collection doesn't exist" do
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

  describe "put/3" do
    test "creates a new entry in the collection for the given collection" do
      collection = insert(:collection)

      assert :ok = Collections.put(collection, "some-key1", "some-value1")
      assert :ok = Collections.put(collection, "some-key12", "some-value12")

      assert %{key: "some-key1", value: "some-value1"} =
               Repo.get_by!(Item, key: "some-key1")

      assert %{key: "some-key12", value: "some-value12"} =
               Repo.get_by!(Item, key: "some-key12")

      byte_size_sum =
        byte_size("some-key1") + byte_size("some-value1") +
          byte_size("some-key12") + byte_size("some-value12")

      assert %{byte_size_sum: ^byte_size_sum} =
               Repo.get!(Collection, collection.id)
    end

    test "updates the value of an item when key exists" do
      collection = insert(:collection)

      assert :ok = Collections.put(collection, "some-key", "some-value1")

      assert %{key: "some-key", value: "some-value1"} =
               Repo.get_by!(Item, key: "some-key")

      assert :ok = Collections.put(collection, "some-key", "some-value12")

      assert %{key: "some-key", value: "some-value12"} =
               Repo.get_by!(Item, key: "some-key")

      byte_size_sum = byte_size("some-key") + byte_size("some-value12")

      assert %{byte_size_sum: ^byte_size_sum} =
               Repo.get!(Collection, collection.id)
    end

    test "returns an :error if the value is bigger than max len" do
      collection = insert(:collection)

      assert {:error,
              %{
                errors: [
                  value:
                    {"should be at most %{count} character(s)",
                     [
                       count: 1_000_000,
                       validation: :length,
                       kind: :max,
                       type: :string
                     ]}
                ]
              }} =
               Collections.put(
                 collection,
                 "key",
                 String.duplicate("a", 1_000_001)
               )
    end

    test "returns an :error if the collection does not exist" do
      assert {:error,
              %{
                errors: [
                  collection_id:
                    {"does not exist",
                     [
                       constraint: :foreign,
                       constraint_name: "collection_items_collection_id_fkey"
                     ]}
                ]
              }} =
               Collections.put(
                 %Collection{id: Ecto.UUID.generate()},
                 "key",
                 "value"
               )
    end
  end

  describe "put_all/2" do
    test "inserts multiple entries at once in a given collection" do
      collection = insert(:collection)

      {items, storage_used} =
        Enum.map_reduce(10..50, 0, fn i, mem_used ->
          {
            %{"key" => "key#{i}", "value" => "value#{i}"},
            mem_used + byte_size("key#{i}") + byte_size("value#{i}")
          }
        end)

      assert {:ok, 41} = Collections.put_all(collection, items)

      assert Item
             |> Repo.all()
             |> Enum.map(&Map.take(&1, [:key, :value])) ==
               Enum.map(items, fn item ->
                 %{
                   key: item["key"],
                   value: item["value"]
                 }
               end)

      assert %{byte_size_sum: ^storage_used} =
               Repo.get!(Collection, collection.id)
    end

    test "replaces conflicting values and timestamps" do
      collection = insert(:collection)

      items =
        Enum.map(1..5, fn i -> %{"key" => "key#{i}", "value" => "value#{i}"} end)

      assert {:ok, 5} = Collections.put_all(collection, items)

      assert %{updated_at: updated_at1} = Repo.get_by(Item, key: "key1")
      assert %{updated_at: updated_at2} = Repo.get_by(Item, key: "key2")
      assert %{updated_at: updated_at5} = Repo.get_by(Item, key: "key5")

      update_items =
        Enum.map(1..2, fn i ->
          %{"key" => "key#{i}", "value" => "value#{10 + i}"}
        end)

      assert {:ok, 2} = Collections.put_all(collection, update_items)

      assert %{value: "value11", updated_at: updated_at} =
               Repo.get_by(Item, key: "key1")

      assert DateTime.after?(updated_at, updated_at1)

      assert %{value: "value12", updated_at: updated_at} =
               Repo.get_by(Item, key: "key2")

      assert DateTime.after?(updated_at, updated_at2)

      assert %{value: "value5", updated_at: ^updated_at5} =
               Repo.get_by(Item, key: "key5")

      final_items = Enum.drop(items, 2) ++ update_items

      assert Item
             |> Repo.all()
             |> Enum.map(&Map.take(&1, [:key, :value])) ==
               Enum.map(final_items, fn item ->
                 %{
                   key: item["key"],
                   value: item["value"]
                 }
               end)

      storage_used =
        Enum.map(final_items, &(byte_size(&1["key"]) + byte_size(&1["value"])))
        |> Enum.sum()

      assert %{byte_size_sum: ^storage_used} =
               Repo.get!(Collection, collection.id)
    end

    test "raises Postgrex error when an item is bigger than allowed max len" do
      collection = insert(:collection)

      items = [
        %{"key" => "key1", "value" => "adsf"},
        %{"key" => "key1", "value" => String.duplicate("a", 1_000_001)}
      ]

      assert_raise Postgrex.Error, fn ->
        Collections.put_all(collection, items)
      end
    end
  end

  describe "delete/2" do
    test "deletes an entry for the given collection" do
      collection = insert(:collection)

      key1 = "áàâãäéèêëíìîï"
      key2 = "óòôõöúùûüçñabc"

      :ok = Collections.put(collection, key1, "12345")
      :ok = Collections.put(collection, key2, "12345")

      assert Collections.get(collection, key1)
      assert Collections.get(collection, key2)

      assert :ok = Collections.delete(collection, key1)

      refute Collections.get(collection, key1)
      assert Collections.get(collection, key2)

      byte_size2 = byte_size(key2) + byte_size("12345")

      assert %{byte_size_sum: ^byte_size2} =
               Repo.get!(Collection, collection.id)
    end

    test "returns an :error if the collection does not exist" do
      assert {:error, :not_found} =
               Collections.delete(%{id: Ecto.UUID.generate()}, "key")
    end

    test "returns an :error if item does not exist" do
      collection = insert(:collection)

      assert {:error, :not_found} =
               Collections.delete(collection, "nonexistent")
    end
  end

  describe "delete_all/2" do
    test "does nothing on an empty collection" do
      collection = insert(:collection)

      assert %{byte_size_sum: 0} = Repo.get!(Collection, collection.id)

      assert {:ok, 0} = Collections.delete_all(collection, "*")
    end

    test "deletes all items of the given collection" do
      collection = insert(:collection)

      items = insert_list(3, :collection_item, collection: collection)

      assert {:ok, 3} = Collections.delete_all(collection)

      refute Enum.any?(items, &Collections.get(collection, &1.key))

      assert %{byte_size_sum: 0} = Repo.get!(Collection, collection.id)
    end

    test "deletes matching items of the given collection" do
      collection = insert(:collection)

      :ok = Collections.put(collection, "foo:111:bär1", "12345")
      :ok = Collections.put(collection, "foo:222:bär2", "12345")
      :ok = Collections.put(collection, "foo:333:bär3", "12345")
      :ok = Collections.put(collection, "foo:444:bár4", "12345")

      item4_size = byte_size("foo:444:bár4") + byte_size("12345")

      collection_size =
        item4_size + 3 * (byte_size("foo:333:bär3") + byte_size("12345"))

      assert %{byte_size_sum: ^collection_size} =
               Repo.get!(Collection, collection.id)

      assert Collections.get(collection, "foo:111:bär1")
      assert Collections.get(collection, "foo:222:bär2")
      assert Collections.get(collection, "foo:333:bär3")

      assert {:ok, 3} = Collections.delete_all(collection, "foo:*:bär*")

      refute Collections.get(collection, "foo:111:bär1")
      refute Collections.get(collection, "foo:222:bär2")
      refute Collections.get(collection, "foo:333:bär3")
      assert Collections.get(collection, "foo:444:bár4")

      assert %{byte_size_sum: ^item4_size} = Repo.get!(Collection, collection.id)
    end

    test "deletes all items by matching on the given collection" do
      collection = insert(:collection)

      :ok = Collections.put(collection, "foo:111:bär1", "12345")
      :ok = Collections.put(collection, "foo:222:bär2", "12345")

      collection_size = 2 * (byte_size("foo:nnn:bärn") + byte_size("12345"))

      assert %{byte_size_sum: ^collection_size} =
               Repo.get!(Collection, collection.id)

      assert Collections.get(collection, "foo:111:bär1")
      assert Collections.get(collection, "foo:222:bär2")

      assert {:ok, 2} = Collections.delete_all(collection, "foo:*:bär*")

      refute Collections.get(collection, "foo:111:bär1")
      refute Collections.get(collection, "foo:222:bär2")

      assert %{byte_size_sum: 0} = Repo.get!(Collection, collection.id)
    end

    test "deletes matching all items on the given collection" do
      collection = insert(:collection)

      :ok = Collections.put(collection, "foo:111:bär1", "12345")
      :ok = Collections.put(collection, "foo:222:bär2", "12345")

      collection_size = 2 * (byte_size("foo:nnn:bärn") + byte_size("12345"))

      assert %{byte_size_sum: ^collection_size} =
               Repo.get!(Collection, collection.id)

      assert Collections.get(collection, "foo:111:bär1")
      assert Collections.get(collection, "foo:222:bär2")

      assert {:ok, 2} = Collections.delete_all(collection, "*")

      refute Collections.get(collection, "foo:111:bär1")
      refute Collections.get(collection, "foo:222:bär2")

      assert %{byte_size_sum: 0} = Repo.get!(Collection, collection.id)
    end

    test "returns an :error if the collection does not exist" do
      assert {:error, :not_found} =
               Collections.delete(%{id: Ecto.UUID.generate()}, "key")
    end

    test "returns an :error if item does not exist" do
      collection = insert(:collection)

      assert {:error, :not_found} =
               Collections.delete(collection, "nonexistent")
    end
  end

  describe "list_collections/1" do
    test "returns a list of collections with default ordering and preloading" do
      collection1 = insert(:collection, name: "B Collection")
      collection2 = insert(:collection, name: "A Collection")

      result = Collections.list_collections()

      assert Enum.map(result, & &1.id) == [collection2.id, collection1.id]
    end

    test "returns collections ordered by specified field" do
      collection1 = insert(:collection, inserted_at: ~N[2024-01-01 00:00:00])
      collection2 = insert(:collection, inserted_at: ~N[2024-02-01 00:00:00])

      result = Collections.list_collections(order_by: [asc: :inserted_at])

      assert Enum.map(result, & &1.id) == [collection1.id, collection2.id]
    end

    test "preloads specified associations" do
      project = insert(:project)
      insert(:collection, project: project)

      result = Collections.list_collections(preload: [:project])

      assert Enum.map(result, & &1.project.id) == [project.id]
    end
  end

  describe "create_collection/1" do
    test "creates a new collection with valid attributes" do
      %{id: project_id} = insert(:project)
      attrs = %{"name" => "new-collection", "project_id" => project_id}

      assert {:ok, %Collection{name: "new-collection"}} =
               Collections.create_collection(attrs)
    end

    test "returns an error if invalid attributes are provided" do
      attrs = %{"name" => nil, "project_id" => Ecto.UUID.generate()}

      assert {:error, changeset} = Collections.create_collection(attrs)

      assert %{name: ["can't be blank"]} == errors_on(changeset)
    end
  end

  describe "update_collection/2" do
    test "updates an existing collection with valid attributes" do
      collection = insert(:collection, name: "Old Name")
      attrs = %{name: "updated-name"}

      assert {:ok, %Collection{name: "updated-name"}} =
               Collections.update_collection(collection, attrs)
    end

    test "returns an error if invalid attributes are provided" do
      collection = insert(:collection)
      attrs = %{name: nil}

      assert {:error, changeset} =
               Collections.update_collection(collection, attrs)

      assert %{name: ["can't be blank"]} == errors_on(changeset)
    end
  end

  defp item_reload(item) do
    # composite primary
    Repo.get_by(Item, id: item.id, collection_id: item.collection_id)
  end
end
