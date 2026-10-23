defmodule Lightning.CollectionsItemWritingTest do
  use Lightning.DataCase, async: true

  alias Lightning.Collections
  alias Lightning.Collections.Collection
  alias Lightning.Collections.Item

  describe "Item.changeset/2 column width" do
    # Key width only. Null bytes in item keys are not covered here.
    test "a key short in graphemes but too wide for the column is rejected" do
      collection = insert(:collection)
      family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"

      changeset =
        Item.changeset(%Item{}, %{
          collection_id: collection.id,
          key: String.duplicate(family, 200),
          value: "v"
        })

      assert errors_on(changeset)[:key] == [
               "key is too long, please use a shorter one"
             ]
    end

    test "a value short in graphemes but too wide for the column is rejected" do
      collection = insert(:collection)
      family = "\u{1F468}\u{200D}\u{1F469}\u{200D}\u{1F467}\u{200D}\u{1F466}"

      # 200_000 graphemes, which clears the 1_000_000 grapheme cap, but
      # 1_400_000 codepoints, which is what varchar(1000000) counts.
      changeset =
        Item.changeset(%Item{}, %{
          collection_id: collection.id,
          key: "k",
          value: String.duplicate(family, 200_000)
        })

      assert errors_on(changeset)[:value] == [
               "value is too long, please use a shorter one"
             ]
    end

    test "a value wider than the limit in bytes but not in characters is accepted" do
      collection = insert(:collection)

      changeset =
        Item.changeset(%Item{}, %{
          collection_id: collection.id,
          key: "k",
          value: String.duplicate("é", 1_000_000)
        })

      assert changeset.valid?
    end

    test "a key at the column width is accepted" do
      collection = insert(:collection)

      changeset =
        Item.changeset(%Item{}, %{
          collection_id: collection.id,
          key: String.duplicate("a", 255),
          value: "v"
        })

      refute errors_on(changeset)[:key]
      assert {:ok, _} = Repo.insert(changeset)
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

    test "refuses a key too long to store with a changeset erring on :key" do
      collection = insert(:collection)

      assert {:error, %Ecto.Changeset{errors: errors}} =
               Collections.put(collection, String.duplicate("k", 256), "v")

      assert [{:key, {"key is too long, please use a shorter one", _opts}}] =
               errors
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

    test "refuses a value that isn't a string" do
      collection = insert(:collection)

      assert {:error, changeset} =
               Collections.put(collection, "key", %{"nested" => true})

      assert changeset.errors == [
               value: {"is invalid", [type: :string, validation: :cast]}
             ]
    end

    test "answers the hook's size refusal as a limit, writing nothing" do
      collection = insert(:collection)
      message = %Lightning.Extensions.Message{text: "over the limit"}

      Mox.stub(
        Lightning.Extensions.MockCollectionHook,
        :handle_put_items,
        fn _collection, _size -> {:error, :exceeds_limit, message} end
      )

      assert {:error, :exceeds_limit, ^message} =
               Collections.put(collection, "key", "value")

      assert Repo.all(Item) == []
    end

    test "refuses an invalid value before asking the hook about its size" do
      collection = insert(:collection)

      Mox.expect(
        Lightning.Extensions.MockCollectionHook,
        :handle_put_items,
        0,
        fn _collection, _size -> :ok end
      )

      assert {:error, %Ecto.Changeset{}} =
               Collections.put(
                 collection,
                 "key",
                 String.duplicate("a", 1_000_001)
               )

      Mox.verify!()
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

    test "refuses every item whose key an earlier item uses, at its position" do
      collection = insert(:collection)

      items =
        Enum.map(
          ["a", "b", "a", "a"],
          &%{"key" => &1, "value" => "v"}
        )

      assert {:error, changeset} = Collections.put_all(collection, items)

      assert Enum.sort(changeset.errors) ==
               Enum.sort(
                 items:
                   {"names the same key as #/items/0",
                    [code: :duplicate, key: ["items", 2, "key"]]},
                 items:
                   {"names the same key as #/items/0",
                    [code: :duplicate, key: ["items", 3, "key"]]}
               )

      assert Repo.all(Item) == []
    end

    test "refuses invalid items at their positions, writing none of the list" do
      collection = insert(:collection)

      items = [
        %{"key" => "ok", "value" => "v"},
        %{"key" => "missing-value"},
        %{"key" => "too-long", "value" => String.duplicate("a", 1_000_001)},
        "not an object",
        %{"key" => "not-a-string", "value" => %{"nested" => true}}
      ]

      assert {:error, changeset} = Collections.put_all(collection, items)

      assert Enum.sort(changeset.errors) ==
               Enum.sort(
                 items:
                   {"can't be blank",
                    [key: ["items", 1, :value], validation: :required]},
                 items:
                   {"should be at most %{count} character(s)",
                    [
                      key: ["items", 2, :value],
                      count: 1_000_000,
                      validation: :length,
                      kind: :max,
                      type: :string
                    ]},
                 items:
                   {"is invalid",
                    [key: ["items", 3], validation: :cast, type: :map]},
                 items:
                   {"is invalid",
                    [
                      key: ["items", 4, :value],
                      type: :string,
                      validation: :cast
                    ]}
               )

      assert Repo.all(Item) == []
    end

    test "refuses items that aren't a list" do
      collection = insert(:collection)

      assert {:error, changeset} = Collections.put_all(collection, "items")

      assert changeset.errors == [
               items: {"is invalid", [validation: :cast, type: {:array, :map}]}
             ]
    end

    test "answers the hook's size refusal as a limit, writing nothing" do
      collection = insert(:collection)
      message = %Lightning.Extensions.Message{text: "over the limit"}

      Mox.stub(
        Lightning.Extensions.MockCollectionHook,
        :handle_put_items,
        fn _collection, _size -> {:error, :exceeds_limit, message} end
      )

      assert {:error, :exceeds_limit, ^message} =
               Collections.put_all(collection, [
                 %{"key" => "k", "value" => "v"}
               ])

      assert Repo.all(Item) == []
    end

    test "refuses an invalid list before asking the hook about its size" do
      collection = insert(:collection)

      Mox.expect(
        Lightning.Extensions.MockCollectionHook,
        :handle_put_items,
        0,
        fn _collection, _size -> :ok end
      )

      assert {:error, %Ecto.Changeset{}} =
               Collections.put_all(collection, [
                 %{"key" => "k", "value" => "v"},
                 %{"key" => "k", "value" => "v"}
               ])

      Mox.verify!()
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

    test "answers not_found for an item or a collection that doesn't exist" do
      collection = insert(:collection)

      assert {:error, :not_found} =
               Collections.delete(collection, "nonexistent")

      assert {:error, :not_found} =
               Collections.delete(%{id: Ecto.UUID.generate()}, "key")
    end
  end

  describe "delete_all/2" do
    test "deletes all items of the given collection" do
      collection = insert(:collection)

      items = insert_list(3, :collection_item, collection: collection)

      assert {:ok, 3} = Collections.delete_all(collection)

      refute Enum.any?(items, &Collections.get(collection, &1.key))

      assert %{byte_size_sum: 0} = Repo.get!(Collection, collection.id)
    end

    test "deletes the items matching a pattern and leaves the rest" do
      collection = insert(:collection)

      for key <- ["foo:111:bär1", "foo:222:bär2", "foo:333:bär3", "foo:444:bár4"],
          do: :ok = Collections.put(collection, key, "12345")

      kept_size = byte_size("foo:444:bár4") + byte_size("12345")

      assert {:ok, 3} = Collections.delete_all(collection, "foo:*:bär*")

      assert [%Item{key: "foo:444:bár4"}] =
               Collections.get_all(collection, %{limit: 50})

      assert %{byte_size_sum: ^kept_size} =
               Repo.get!(Collection, collection.id)
    end

    test "deletes every item for the match-all pattern, and nothing from an empty collection" do
      collection = insert(:collection)

      :ok = Collections.put(collection, "foo:111:bär1", "12345")
      :ok = Collections.put(collection, "foo:222:bär2", "12345")

      assert {:ok, 2} = Collections.delete_all(collection, "*")

      assert [] = Collections.get_all(collection, %{limit: 50})
      assert %{byte_size_sum: 0} = Repo.get!(Collection, collection.id)
      assert {:ok, 0} = Collections.delete_all(collection, "*")
    end
  end
end
