defmodule LightningWeb.API.CollectionsStreamingTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.ApiCollectionsHelpers

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  setup :member_with_collection

  describe "listing a collection" do
    test "answers no items and no cursor for an empty collection", %{
      conn: conn,
      collection: collection
    } do
      conn = get(conn, ~p"/collections/#{collection.name}")

      assert json_response(conn, 200) == %{"items" => [], "cursor" => nil}
    end

    test "streams the answer in chunks", %{conn: conn, collection: collection} do
      conn = get(conn, ~p"/collections/#{collection.name}")

      assert conn.state == :chunked
    end

    test "narrows by key pattern", %{conn: conn, collection: collection} do
      insert(:collection_item, collection: collection, key: "foo:bar:baz")
      insert(:collection_item, collection: collection, key: "foo:bar:baz:quux")

      for {pattern, keys} <- [
            {"foo:bar:*", ["foo:bar:baz", "foo:bar:baz:quux"]},
            {"foo:*:baz", ["foo:bar:baz"]}
          ] do
        conn = get(conn, ~p"/collections/#{collection.name}?#{%{key: pattern}}")

        assert %{"items" => items, "cursor" => nil} = json_response(conn, 200)
        assert Enum.map(items, & &1["key"]) == keys
      end
    end

    test "narrows by key pattern and creation time", %{
      conn: conn,
      collection: collection
    } do
      before_insert = DateTime.utc_now()

      insert(:collection_item, collection: collection, key: "foo:bar:baz")
      insert(:collection_item, collection: collection, key: "foo:moon:baz")
      insert(:collection_item, collection: collection, key: "foo:bar:baz:out")

      after_insert = DateTime.utc_now() |> DateTime.add(10, :millisecond)

      for {params, keys} <- [
            {[created_after: DateTime.to_iso8601(after_insert)], []},
            {[created_before: DateTime.to_iso8601(before_insert)], []},
            {[
               created_after: DateTime.to_iso8601(before_insert),
               created_before: DateTime.to_iso8601(after_insert)
             ], ["foo:bar:baz", "foo:moon:baz"]}
          ] do
        conn =
          get(
            conn,
            ~p"/collections/#{collection.name}",
            [key: "foo:*:baz"] ++ params
          )

        assert %{"items" => items, "cursor" => nil} = json_response(conn, 200)
        assert Enum.map(items, & &1["key"]) == keys
      end
    end

    test "narrows by key pattern and update time", %{
      conn: conn,
      collection: collection
    } do
      before_insert = DateTime.utc_now()

      insert(:collection_item, collection: collection, key: "foo:bar:baz")
      insert(:collection_item, collection: collection, key: "foo:moon:baz")
      insert(:collection_item, collection: collection, key: "foo:bar:baz:out")

      after_insert = DateTime.utc_now() |> DateTime.add(10, :millisecond)

      insert(:collection_item,
        collection: collection,
        key: "foo:in:baz",
        updated_at: DateTime.add(after_insert, 1, :millisecond)
      )

      for {params, keys} <- [
            {[updated_after: DateTime.to_iso8601(after_insert)], ["foo:in:baz"]},
            {[updated_before: DateTime.to_iso8601(before_insert)], []},
            {[
               updated_after: DateTime.to_iso8601(before_insert),
               updated_before: DateTime.to_iso8601(after_insert)
             ], ["foo:bar:baz", "foo:moon:baz"]}
          ] do
        conn =
          get(
            conn,
            ~p"/collections/#{collection.name}",
            [key: "foo:*:baz"] ++ params
          )

        assert %{"items" => items, "cursor" => nil} = json_response(conn, 200)
        assert Enum.map(items, & &1["key"]) == keys
      end
    end

    test "narrows by creation time", %{conn: conn, collection: collection} do
      before_insert = DateTime.utc_now()
      items = insert_list(3, :collection_item, collection: collection)
      after_insert = DateTime.utc_now() |> DateTime.add(10, :millisecond)

      items = Enum.map(items, &encode_decode/1)

      for params <- [
            [created_after: DateTime.to_iso8601(before_insert)],
            [created_before: DateTime.to_iso8601(after_insert)],
            []
          ] do
        conn = get(conn, ~p"/collections/#{collection.name}", params)

        assert json_response(conn, 200) == %{"items" => items, "cursor" => nil}
      end
    end

    test "narrows by update time", %{conn: conn, collection: collection} do
      old_item =
        insert(:collection_item, collection: collection, key: "old-key")
        |> encode_decode()

      before_insert_list = DateTime.utc_now()

      items =
        insert_list(3, :collection_item, collection: collection)
        |> Enum.map(&encode_decode/1)

      after_insert = DateTime.utc_now() |> DateTime.add(10, :millisecond)

      for {params, expected} <- [
            {[updated_after: DateTime.to_iso8601(before_insert_list)], items},
            {[updated_before: DateTime.to_iso8601(after_insert)],
             [old_item | items]},
            {[], [old_item | items]}
          ] do
        conn = get(conn, ~p"/collections/#{collection.name}", params)

        assert json_response(conn, 200) == %{
                 "items" => expected,
                 "cursor" => nil
               }
      end
    end
  end

  describe "page size and cursors" do
    test "up to the default limit", %{conn: conn, collection: collection} do
      default_limit = 25

      Mox.stub(Lightning.MockConfig, :collections_default_stream_limit, fn ->
        default_limit
      end)

      items = insert_list(3, :collection_item, collection: collection)

      conn = get(conn, ~p"/collections/#{collection.name}")

      items = Enum.map(items, &encode_decode/1)

      assert json_response(conn, 200) == %{"items" => items, "cursor" => nil}

      # Insert more to bring the total to the stream limit
      items =
        Enum.concat(
          items,
          insert_list(
            default_limit - length(items),
            :collection_item,
            collection: collection
          )
          |> Enum.map(&encode_decode/1)
        )

      conn = get(conn, ~p"/collections/#{collection.name}")

      assert json_response(conn, 200) == %{"items" => items, "cursor" => nil}
    end

    test "up to a limit from params", %{conn: conn, collection: collection} do
      page_size = 15

      Mox.stub(Lightning.MockConfig, :collections_stream_page_size, fn ->
        page_size
      end)

      limit = page_size + 10

      all_items =
        insert_list(limit + 1, :collection_item, collection: collection)
        |> Enum.map(&encode_decode/1)

      conn = get(conn, ~p"/collections/#{collection.name}", limit: limit)

      assert %{"items" => items, "cursor" => cursor} = json_response(conn, 200)
      assert items == Enum.take(all_items, limit)
      assert cursor

      conn =
        get(conn, ~p"/collections/#{collection.name}",
          limit: limit,
          cursor: cursor
        )

      assert json_response(conn, 200) == %{
               "items" => Enum.drop(all_items, limit),
               "cursor" => nil
             }

      # A limit below the page size still leaves a cursor to the rest
      half_limit = div(page_size, 2)

      conn = get(conn, ~p"/collections/#{collection.name}", limit: half_limit)

      assert %{"items" => items, "cursor" => cursor} = json_response(conn, 200)
      assert items == Enum.take(all_items, half_limit)
      assert cursor

      # Request everything, shouldn't be getting a cursor
      conn = get(conn, ~p"/collections/#{collection.name}", limit: limit + 1)

      assert json_response(conn, 200) == %{"items" => all_items, "cursor" => nil}
    end

    test "answers no items for a limit of 0", %{
      conn: conn,
      collection: collection
    } do
      insert(:collection_item, collection: collection)

      conn = get(conn, ~p"/collections/#{collection.name}", limit: "0")

      assert json_response(conn, 200) == %{"items" => [], "cursor" => nil}
    end

    test "up to the default limit and returning a cursor", %{
      conn: conn,
      collection: collection
    } do
      default_limit = 25

      Mox.stub(Lightning.MockConfig, :collections_default_stream_limit, fn ->
        default_limit
      end)

      all_items =
        insert_list(default_limit + 1, :collection_item, collection: collection)
        |> Enum.map(&encode_decode/1)

      conn = get(conn, ~p"/collections/#{collection.name}")

      assert %{"items" => items, "cursor" => cursor} = json_response(conn, 200)
      assert items == Enum.take(all_items, default_limit)
      assert cursor

      conn = get(conn, ~p"/collections/#{collection.name}", cursor: cursor)

      assert json_response(conn, 200) == %{
               "items" => Enum.drop(all_items, default_limit),
               "cursor" => nil
             }
    end

    test "up to the limit from a cursor returning a cursor", %{
      conn: conn,
      collection: collection
    } do
      limit = 100

      all_items =
        insert_list(2 * limit + 1, :collection_item, collection: collection)
        |> Enum.map(&encode_decode/1)

      conn = get(conn, ~p"/collections/#{collection.name}", limit: limit)

      assert %{"items" => items, "cursor" => cursor} = json_response(conn, 200)
      assert items == Enum.take(all_items, limit)

      conn =
        get(conn, ~p"/collections/#{collection.name}",
          cursor: cursor,
          limit: limit
        )

      assert %{"items" => items, "cursor" => cursor} = json_response(conn, 200)
      assert items == all_items |> Enum.drop(limit) |> Enum.take(limit)
      assert cursor

      conn =
        get(conn, ~p"/collections/#{collection.name}",
          cursor: cursor,
          limit: limit
        )

      assert json_response(conn, 200) == %{
               "items" => Enum.drop(all_items, 2 * limit),
               "cursor" => nil
             }
    end

    test "up exactly to the limit from a cursor", %{
      conn: conn,
      collection: collection
    } do
      limit = 25

      all_items =
        insert_list(2 * limit, :collection_item, collection: collection)
        |> Enum.map(&encode_decode/1)

      conn = get(conn, ~p"/collections/#{collection.name}", limit: limit)

      assert %{"items" => items, "cursor" => cursor} = json_response(conn, 200)
      assert items == Enum.take(all_items, limit)

      conn =
        get(conn, ~p"/collections/#{collection.name}",
          cursor: cursor,
          limit: limit
        )

      assert json_response(conn, 200) == %{
               "items" => Enum.drop(all_items, limit),
               "cursor" => nil
             }
    end
  end

  defp encode_decode(item) do
    item
    |> Jason.encode!()
    |> Jason.decode!()
  end
end
