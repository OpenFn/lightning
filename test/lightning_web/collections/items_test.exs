defmodule LightningWeb.API.CollectionsItemsTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.ApiCollectionsHelpers

  alias Lightning.Collections

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  setup :member_with_collection

  describe "reading one item" do
    test "answers the item", %{conn: conn, collection: collection} do
      item =
        insert(:collection_item,
          collection: collection,
          key: "foo",
          value: "bar"
        )

      conn = get(conn, ~p"/collections/#{collection.name}/foo")

      assert json_response(conn, 200) == %{
               "key" => "foo",
               "value" => "bar",
               "created" => DateTime.to_iso8601(item.inserted_at),
               "updated" => DateTime.to_iso8601(item.updated_at)
             }
    end

    test "answers 204 with no body for a key the collection hasn't got", %{
      conn: conn,
      collection: collection
    } do
      conn = get(conn, ~p"/collections/#{collection.name}/some-unexisting-key")

      assert response(conn, 204) == ""
    end
  end

  describe "writing one item" do
    test "creates a new key and replaces an existing one", %{
      conn: conn,
      collection: collection
    } do
      insert(:collection_item, collection: collection, key: "foo", value: "bar")

      for {key, value} <- [{"baz", "qux"}, {"foo", "qux2"}] do
        conn =
          put(conn, ~p"/collections/#{collection.name}/#{key}", value: value)

        assert json_response(conn, 200) == %{"upserted" => 1, "error" => nil}
        assert Collections.get(collection, key).value == value
      end
    end
  end

  describe "writing many items" do
    test "inserts multiple items with same timestamp", %{
      conn: conn,
      collection: collection
    } do
      assert %{"upserted" => 1_000, "error" => nil} =
               post(conn, ~p"/collections/#{collection.name}", %{
                 items:
                   Enum.map(1..1_000, &%{key: "foo#{&1}", value: "bar#{&1}"})
               })
               |> json_response(200)

      assert %{"items" => items, "cursor" => nil} =
               get(conn, ~p"/collections/#{collection.name}", limit: 1_000)
               |> json_response(200)

      assert MapSet.new(items, & &1["created"]) |> MapSet.size() == 1
      assert Enum.count(items) == 1_000
    end

    test "upserts new and existing keys together", %{
      conn: conn,
      collection: collection
    } do
      for n <- 1..3 do
        insert(:collection_item,
          collection: collection,
          key: "foo#{n}",
          value: "old#{n}"
        )
      end

      conn =
        post(conn, ~p"/collections/#{collection.name}", %{
          items: Enum.map(1..10, &%{key: "foo#{&1}", value: "bar#{&1}"})
        })

      assert json_response(conn, 200) == %{"upserted" => 10, "error" => nil}

      assert Enum.map(1..10, &Collections.get(collection, "foo#{&1}").value) ==
               Enum.map(1..10, &"bar#{&1}")
    end
  end

  describe "deleting" do
    test "deletes an item", %{conn: conn, collection: collection} do
      insert(:collection_item, collection: collection, key: "foo", value: "bar")

      conn = delete(conn, ~p"/collections/#{collection.name}/foo")

      assert json_response(conn, 200) == %{
               "key" => "foo",
               "deleted" => 1
             }
    end

    test "returns deleted: 0 when deleting a missing key", %{
      conn: conn,
      collection: collection
    } do
      conn = delete(conn, ~p"/collections/#{collection.name}/missing-key")

      assert json_response(conn, 200) == %{
               "key" => "missing-key",
               "deleted" => 0
             }
    end

    @tag role: :owner
    test "deletes matching items", %{conn: conn, collection: collection} do
      for {key, value} <- [
            {"foo:123:bar1", "value1"},
            {"foo:234:boo", "value2"},
            {"foo:345:bar2", "value3"}
          ] do
        insert(:collection_item, collection: collection, key: key, value: value)
      end

      conn = delete(conn, ~p"/collections/#{collection.name}", key: "foo:*:bar*")

      assert json_response(conn, 200) == %{
               "key" => "foo:*:bar*",
               "deleted" => 2
             }

      assert Collections.get(collection, "foo:234:boo")
    end
  end
end
