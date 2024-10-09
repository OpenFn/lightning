defmodule Lightning.CollectionsTest do
  use Lightning.DataCase

  alias Lightning.Collections
  alias Lightning.Collections.Collection
  alias Lightning.Collections.Item

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
      %{key: key, value: value, collection: %{name: name}} =
        insert(:collection_item) |> Repo.preload(:collection)

      assert {:ok, %Item{key: ^key, value: ^value}} = Collections.get(name, key)
    end

    test "returns an :error if the collection does not exist" do
      insert(:collection_item, key: "existing_key")

      assert {:error, :not_found} = Collections.get("nonexistent", "existing_key")
    end

    test "returns nil if the item key does not exist" do
      collection = insert(:collection)

      assert {:error, :not_found} =
               Collections.get(collection.name, "nonexistent")
    end
  end

  describe "put/3" do
    test "creates a new entry in the collection for the given collection" do
      collection = insert(:collection)

      assert {:ok, entry} = Collections.put(collection.name, "key", "value")

      assert entry.key == "key"
      assert entry.value == "value"
    end

    test "updates the value of an item when key exists" do
      collection = insert(:collection)

      assert {:ok, entry} = Collections.put(collection.name, "key", "value1")

      assert entry.key == "key"
      assert entry.value == "value1"

      assert {:ok, entry} = Collections.put(collection.name, "key", "value2")

      assert entry.key == "key"
      assert entry.value == "value2"
    end

    test "returns an :error if the collection does not exist" do
      assert {:error, %{errors: [collection_name: {"does not exist", [constraint: :foreign, constraint_name: "collections_items_collection_name_fkey"]}]}} = Collections.put("nonexistent", "key", "value")
    end
  end

  describe "delete/2" do
    test "deletes an entry for the given collection" do
      collection = insert(:collection)

      %{key: key} =
        insert(:collection_item, collection: collection) |> Repo.reload()

      assert {:ok, %{key: ^key}} = Collections.delete(collection.name, key)

      assert {:error, :not_found} = Collections.get(collection.name, key)
    end

    test "returns an :error if the collection does not exist" do
      assert {:error, :not_found} = Collections.delete("nonexistent", "key")
    end

    test "returns an :error if item does not exist" do
      collection = insert(:collection)

      assert {:error, :not_found} =
               Collections.delete(collection.name, "nonexistent")
    end
  end
end
