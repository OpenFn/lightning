defmodule Lightning.CollectionsTest do
  use Lightning.DataCase

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
      assert {:error, :collection_not_found} =
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
                    {"has already been taken",
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
      assert {:error, :collection_not_found} =
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

  describe "stream_all/3" do
    test "returns all items for the given collection" do
      collection = insert(:collection)
      items = insert_list(11, :collection_item, collection: collection)

      Repo.transaction(fn ->
        assert stream = Collections.stream_all(collection)
        assert stream_items = Stream.take(stream, 12)

        assert MapSet.new(items) ==
                 stream_items
                 |> Enum.to_list()
                 |> Repo.preload(collection: :project)
                 |> MapSet.new()
      end)
    end

    test "returns the items after a cursor up to a limited amount" do
      collection = insert(:collection)

      items = insert_list(30, :collection_item, collection: collection)
      %{key: cursor} = Enum.at(items, 4)

      Repo.transaction(fn ->
        assert stream = Collections.stream_all(collection, cursor)
        assert Enum.count(stream) == 30 - (4 + 1)
      end)

      Repo.transaction(fn ->
        assert stream = Collections.stream_all(collection, cursor, 10)
        assert Enum.count(stream) == 10
      end)
    end

    test "returns empty list when collection is empty" do
      collection = insert(:collection)

      Repo.transaction(fn ->
        assert stream = Collections.stream_all(collection)
        assert Enum.count(stream) == 0
      end)
    end

    test "returns empty list when the collection doesn't exist" do
      insert(:collection_item, key: "existing_key")

      Repo.transaction(fn ->
        assert stream = Collections.stream_all(%{id: Ecto.UUID.generate()})
        assert Enum.count(stream) == 0
      end)
    end

    test "fails when outside of an explicit transaction" do
      collection = insert(:collection)
      _items = insert_list(5, :collection_item, collection: collection)

      assert stream = Collections.stream_all(collection)

      assert_raise RuntimeError,
                   ~r/cannot reduce stream outside of transaction/,
                   fn ->
                     Enum.take(stream, 5) |> Enum.each(&IO.inspect/1)
                   end
    end
  end

  describe "put/3" do
    test "creates a new entry in the collection for the given collection" do
      collection = insert(:collection)

      assert {:ok, entry} = Collections.put(collection, "key", "value")

      assert entry.key == "key"
      assert entry.value == "value"
    end

    test "updates the value of an item when key exists" do
      collection = insert(:collection)

      assert {:ok, entry} = Collections.put(collection, "key", "value1")

      assert entry.key == "key"
      assert entry.value == "value1"

      assert {:ok, entry} = Collections.put(collection, "key", "value2")

      assert entry.key == "key"
      assert entry.value == "value2"
    end

    test "returns an :error if the collection does not exist" do
      assert {:error,
              %{
                errors: [
                  collection_id:
                    {"does not exist",
                     [
                       constraint: :foreign,
                       constraint_name: "collections_items_collection_id_fkey"
                     ]}
                ]
              }} = Collections.put(%{id: Ecto.UUID.generate()}, "key", "value")
    end
  end

  describe "delete/2" do
    test "deletes an entry for the given collection" do
      collection = insert(:collection)

      %{key: key} =
        insert(:collection_item, collection: collection) |> Repo.reload()

      assert {:ok, %{key: ^key}} = Collections.delete(collection, key)

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
end
