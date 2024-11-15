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
               Collections.create_collection(project_id, name)
    end

    test "returns an error when collection name is taken" do
      %{id: project_id1} = insert(:project)
      %{id: project_id2} = insert(:project)
      name = "col1_project1"

      assert {:ok, %Collection{project_id: ^project_id1, name: ^name}} =
               Collections.create_collection(project_id1, name)

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
              }} = Collections.create_collection(project_id2, name)
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

      %{inserted_at: cursor} = Enum.at(items, 4)

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

      items =
        1..11
        |> Enum.map(fn _i ->
          insert(:collection_item,
            key: "rkeyA#{:rand.uniform()}",
            collection: collection
          )
        end)

      insert(:collection_item, key: "rkeyB", collection: collection)

      get_items =
        Collections.get_all(collection, %{limit: 50}, "rkeyA*")
        |> Repo.preload(collection: :project)

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

      %{inserted_at: cursor} = Enum.at(items, 9)

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
      item = insert(:collection_item, key: "keyA%", collection: collection)

      assert [item] ==
               Collections.get_all(collection, %{limit: 50}, "keyA%*")
               |> Repo.preload(collection: :project)

      insert(:collection_item, key: "keyBC", collection: collection)

      assert [] = Collections.get_all(collection, %{limit: 50}, "keyB%")
    end

    test "returns item escaping the \\" do
      collection = insert(:collection)
      item = insert(:collection_item, key: "keyA\\", collection: collection)

      assert [item] ==
               Collections.get_all(collection, %{limit: 50}, "keyA\\*")
               |> Repo.preload(collection: :project)
    end
  end

  describe "put/3" do
    test "creates a new entry in the collection for the given collection" do
      collection = insert(:collection)

      assert :ok = Collections.put(collection, "some-key", "some-value")

      assert %{key: "some-key", value: "some-value"} =
               Repo.get_by!(Item, key: "some-key")
    end

    test "updates the value of an item when key exists" do
      collection = insert(:collection)

      assert :ok = Collections.put(collection, "some-key", "some-value1")

      assert %{key: "some-key", value: "some-value1"} =
               Repo.get_by!(Item, key: "some-key")

      assert :ok = Collections.put(collection, "some-key", "some-value2")

      assert %{key: "some-key", value: "some-value2"} =
               Repo.get_by!(Item, key: "some-key")
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
              }} = Collections.put(%{id: Ecto.UUID.generate()}, "key", "value")
    end
  end

  describe "put_all/2" do
    test "inserts multiple entries at once in a given collection" do
      collection = insert(:collection)

      items =
        Enum.map(1..5, fn i -> %{"key" => "key#{i}", "value" => "value#{i}"} end)

      assert {:ok, 5} = Collections.put_all(collection, items)

      assert Item |> Repo.all() |> Enum.map(&Map.take(&1, [:key, :value])) ==
               Enum.map(items, &%{key: &1["key"], value: &1["value"]})
    end

    test "replaces conflicting values and updates timestamp" do
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

      assert updated_at > updated_at1

      assert %{value: "value12", updated_at: updated_at} =
               Repo.get_by(Item, key: "key2")

      assert updated_at > updated_at2

      assert %{value: "value5", updated_at: ^updated_at5} =
               Repo.get_by(Item, key: "key5")
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

      %{key: key} =
        insert(:collection_item, collection: collection)

      assert :ok = Collections.delete(collection, key)

      refute Collections.get(collection, key)
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
    test "deletes all items of the given collection" do
      collection = insert(:collection)

      items = insert_list(3, :collection_item, collection: collection)

      assert {:ok, 3} = Collections.delete_all(collection)

      refute Enum.any?(items, &Collections.get(collection, &1.key))
    end

    test "deletes matching items of the given collection" do
      collection = insert(:collection)

      item1 =
        insert(:collection_item, collection: collection, key: "foo:123:bar1")

      item2 =
        insert(:collection_item, collection: collection, key: "foo:234:bar2")

      item3 =
        insert(:collection_item, collection: collection, key: "foo:345:bar3")

      item4 =
        insert(:collection_item, collection: collection, key: "foo:456:zanzibar")

      assert {:ok, 3} = Collections.delete_all(collection, "foo:*:bar*")

      refute Collections.get(collection, item1.key)
      refute Collections.get(collection, item2.key)
      refute Collections.get(collection, item3.key)
      assert Collections.get(collection, item4.key)
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
      attrs = %{name: "new-collection", project_id: project_id}

      assert {:ok, %Collection{name: "new-collection"}} =
               Collections.create_collection(attrs)
    end

    test "returns an error if invalid attributes are provided" do
      attrs = %{name: nil}

      assert {:error, changeset} = Collections.create_collection(attrs)

      assert %{name: ["can't be blank"], project_id: ["can't be blank"]} ==
               errors_on(changeset)
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
end
