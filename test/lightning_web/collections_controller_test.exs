defmodule LightningWeb.API.CollectionsControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  alias Lightning.Collections
  alias Lightning.Extensions.Message

  @limits Application.compile_env!(
            :lightning,
            LightningWeb.CollectionsController
          )

  @default_stream_limit @limits[:default_stream_limit]
  @max_database_limit @limits[:max_database_limit]

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  test "without a token", %{conn: conn} do
    conn = get(conn, ~p"/collections/foo")

    assert %{"error" => "Unauthorized"} == json_response(conn, 401)
  end

  describe "authenticating with a run token" do
    test "with a token that is invalid", %{conn: conn} do
      workflow = insert(:simple_workflow)
      workorder = insert(:workorder, dataclip: insert(:dataclip))

      collection = insert(:collection, project: workflow.project)

      run =
        insert(:run,
          work_order: workorder,
          dataclip: workorder.dataclip,
          starting_trigger: workflow.triggers |> hd()
        )

      token = Lightning.Workers.generate_run_token(run)

      conn =
        conn
        |> assign_bearer(token)
        |> get(~p"/collections/#{collection.name}")

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "authenticating with a personal access token" do
    test "with a project they don't have access to", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [])

      collection = insert(:collection, project: project)

      token = Lightning.Accounts.generate_api_token(user)

      conn =
        conn
        |> assign_bearer(token)
        |> get(~p"/collections/#{collection.name}")

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "GET /collections/:name/:key" do
    test "returns the item", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      collection =
        insert(:collection,
          project: project,
          items: [%{key: "foo", value: "bar"}]
        )

      token = Lightning.Accounts.generate_api_token(user)

      conn =
        conn
        |> assign_bearer(token)
        |> get(~p"/collections/#{collection.name}/foo")

      item = hd(collection.items)

      assert json_response(conn, 200) == %{
               "key" => item.key,
               "value" => item.value,
               "created" => DateTime.to_iso8601(item.inserted_at),
               "updated" => DateTime.to_iso8601(item.updated_at)
             }
    end

    test "returns 404 when the collection doesn't exist", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      _another_collection = insert(:collection, project: project)

      token = Lightning.Accounts.generate_api_token(user)

      conn =
        conn
        |> assign_bearer(token)
        |> get(~p"/collections/misspelled-collection/foo")

      assert json_response(conn, 404) == %{"error" => "Not Found"}
    end

    test "returns 404 when the item doesn't exist", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      collection = insert(:collection, project: project)

      token = Lightning.Accounts.generate_api_token(user)

      conn =
        conn
        |> assign_bearer(token)
        |> get(~p"/collections/#{collection.name}/some-unexisting-key")

      assert response(conn, 204) == ""
    end
  end

  describe "PUT /collections/:name/:key" do
    test "inserts an item", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      collection =
        insert(:collection,
          project: project,
          items: [%{key: "foo", value: "bar"}]
        )

      token = Lightning.Accounts.generate_api_token(user)

      conn =
        conn
        |> assign_bearer(token)
        |> put(~p"/collections/#{collection.name}/baz", value: "qux")

      assert json_response(conn, 200) == %{
               "upserted" => 1,
               "error" => nil
             }
    end

    test "updates an item", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      collection =
        insert(:collection,
          project: project,
          items: [%{key: "foo", value: "bar"}]
        )

      token = Lightning.Accounts.generate_api_token(user)

      conn =
        conn
        |> assign_bearer(token)
        |> put(~p"/collections/#{collection.name}/foo", value: "qux2")

      assert json_response(conn, 200) == %{
               "upserted" => 1,
               "error" => nil
             }
    end

    test "returns 404 when the collection doesn't exist", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      _another_collection = insert(:collection, project: project)

      token = Lightning.Accounts.generate_api_token(user)

      conn =
        conn
        |> assign_bearer(token)
        |> put(~p"/collections/misspelled-collection/baz", value: "qux")

      assert json_response(conn, 404) == %{"error" => "Not Found"}
    end

    test "returns 422 when request exceeds the limit", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      collection =
        insert(:collection,
          project: project,
          items: Enum.map(1..2, &%{key: "foo#{&1}", value: "bar#{&1}"})
        )

      Mox.stub(
        Lightning.Extensions.MockCollectionHook,
        :handle_put_items,
        fn _collection, _size ->
          {:error, :exceeds_limit, %Message{text: "some limit error message"}}
        end
      )

      conn =
        conn
        |> assign_bearer(Lightning.Accounts.generate_api_token(user))
        |> put(~p"/collections/#{collection.name}/foo2", value: "bar22")

      assert json_response(conn, 422) == %{
               "upserted" => 0,
               "error" => "some limit error message"
             }
    end
  end

  describe "POST /collections/:name" do
    test "inserts multiple items with same timestamp", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      collection = insert(:collection, project: project)

      token = Lightning.Accounts.generate_api_token(user)

      conn = assign_bearer(conn, token)

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

    test "upserted multiple items", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      collection =
        insert(:collection,
          project: project,
          items: Enum.map(1..3, &%{key: "foo#{&1}", value: "bar#{&1}"})
        )

      token = Lightning.Accounts.generate_api_token(user)

      conn =
        conn
        |> assign_bearer(token)
        |> post(~p"/collections/#{collection.name}", %{
          items: Enum.map(1..10, &%{key: "foo#{&1}", value: "bar#{&1}"})
        })

      assert json_response(conn, 200) == %{
               "upserted" => 10,
               "error" => nil
             }
    end

    test "returns 404 when the collection doesn't exist", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      _another_collection = insert(:collection, project: project)

      token = Lightning.Accounts.generate_api_token(user)

      conn =
        conn
        |> assign_bearer(token)
        |> post(~p"/collections/misspelled-collection", %{
          items: [%{key: "baz", value: "qux"}]
        })

      assert json_response(conn, 404) == %{"error" => "Not Found"}
    end

    test "returns 422 when request exceeds the limit", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      collection =
        insert(:collection,
          project: project,
          items: Enum.map(1..3, &%{key: "foo#{&1}", value: "bar#{&1}"})
        )

      Mox.stub(
        Lightning.Extensions.MockCollectionHook,
        :handle_put_items,
        fn _collection, _size ->
          {:error, :exceeds_limit, %Message{text: "some limit error message"}}
        end
      )

      conn =
        conn
        |> assign_bearer(Lightning.Accounts.generate_api_token(user))
        |> post(~p"/collections/#{collection.name}", %{
          items: [%{key: "foo4", value: "bar4"}, %{key: "foo5", value: "bar5"}]
        })

      assert json_response(conn, 422) == %{
               "upserted" => 0,
               "error" => "some limit error message"
             }
    end

    test "returns 422 when a key is referenced twice", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      collection =
        insert(:collection,
          project: project,
          items: Enum.map(1..3, &%{key: "foo#{&1}", value: "bar#{&1}"})
        )

      token = Lightning.Accounts.generate_api_token(user)

      conn =
        conn
        |> assign_bearer(token)
        |> post(~p"/collections/#{collection.name}", %{
          items: [%{key: "foo1", value: "bar1"}, %{key: "foo1", value: "bar1"}]
        })

      assert json_response(conn, 422) == %{
               "upserted" => 0,
               "error" => "Duplicate key found"
             }
    end
  end

  describe "DELETE" do
    test "deletes an item", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      collection =
        insert(:collection,
          project: project,
          items: [%{key: "foo", value: "bar"}]
        )

      token = Lightning.Accounts.generate_api_token(user)

      conn =
        conn
        |> assign_bearer(token)
        |> delete(~p"/collections/#{collection.name}/foo")

      assert json_response(conn, 200) == %{
               "key" => "foo",
               "deleted" => 1,
               "error" => nil
             }
    end

    test "deletes matching items", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      collection =
        insert(:collection,
          project: project,
          items: [
            %{key: "foo:123:bar1", value: "value1"},
            %{key: "foo:234:boo", value: "value2"},
            %{key: "foo:345:bar2", value: "value3"}
          ]
        )

      token = Lightning.Accounts.generate_api_token(user)

      conn =
        conn
        |> assign_bearer(token)
        |> delete(~p"/collections/#{collection.name}", key: "foo:*:bar*")

      assert json_response(conn, 200) == %{
               "key" => "foo:*:bar*",
               "deleted" => 2,
               "error" => nil
             }
    end

    test "returns 404 when the collection doesn't exist", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      _another_collection = insert(:collection, project: project)

      token = Lightning.Accounts.generate_api_token(user)

      conn =
        conn
        |> assign_bearer(token)
        |> delete(~p"/collections/misspelled-collection/foo")

      assert json_response(conn, 404) == %{"error" => "Not Found"}
    end
  end

  describe "GET /collections/:name" do
    test "with no results", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      collection = insert(:collection, project: project)

      token = Lightning.Accounts.generate_api_token(user)

      conn =
        conn
        |> assign_bearer(token)
        |> get(~p"/collections/#{collection.name}")

      assert json_response(conn, 200) == %{"items" => [], "cursor" => nil}
    end

    test "using a key pattern", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      collection = insert(:collection, project: project)

      insert(:collection_item, collection: collection, key: "foo:bar:baz")
      insert(:collection_item, collection: collection, key: "foo:bar:baz:quux")

      token = Lightning.Accounts.generate_api_token(user)

      conn = assign_bearer(conn, token)

      assert %{state: :chunked} =
               conn =
               get(
                 conn,
                 ~p"/collections/#{collection.name}?#{%{key: "foo:bar:*"}}"
               )

      assert %{
               "items" => [
                 %{"key" => "foo:bar:baz", "value" => _},
                 %{"key" => "foo:bar:baz:quux", "value" => _}
               ],
               "cursor" => nil
             } = json_response(conn, 200)

      assert %{state: :chunked} =
               conn =
               get(
                 conn,
                 ~p"/collections/#{collection.name}?#{%{key: "foo:*:baz"}}"
               )

      assert %{
               "items" => [%{"key" => "foo:bar:baz", "value" => _}],
               "cursor" => nil
             } = json_response(conn, 200)
    end

    test "using a key pattern and creation filters", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      collection = insert(:collection, project: project)

      before_insert = DateTime.utc_now()

      insert(:collection_item, collection: collection, key: "foo:bar:baz")
      insert(:collection_item, collection: collection, key: "foo:moon:baz")
      insert(:collection_item, collection: collection, key: "foo:bar:baz:out")

      after_insert = DateTime.utc_now() |> DateTime.add(10, :millisecond)

      token = Lightning.Accounts.generate_api_token(user)

      conn = assign_bearer(conn, token)

      assert %{
               "items" => [],
               "cursor" => nil
             } =
               conn
               |> get(~p"/collections/#{collection.name}",
                 key: "foo:*:baz",
                 created_after: DateTime.to_iso8601(after_insert)
               )
               |> json_response(200)

      assert %{
               "items" => [],
               "cursor" => nil
             } =
               conn
               |> get(~p"/collections/#{collection.name}",
                 key: "foo:*:baz",
                 created_before: DateTime.to_iso8601(before_insert)
               )
               |> json_response(200)

      assert %{
               "items" => [
                 %{"key" => "foo:bar:baz", "value" => _},
                 %{"key" => "foo:moon:baz", "value" => _}
               ],
               "cursor" => nil
             } =
               conn
               |> get(~p"/collections/#{collection.name}",
                 key: "foo:*:baz",
                 created_after: DateTime.to_iso8601(before_insert),
                 created_before: DateTime.to_iso8601(after_insert)
               )
               |> json_response(200)
    end

    test "using a key pattern and update filters", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      collection = insert(:collection, project: project)

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

      token = Lightning.Accounts.generate_api_token(user)

      conn = assign_bearer(conn, token)

      assert %{
               "items" => [%{"key" => "foo:in:baz", "value" => _}],
               "cursor" => nil
             } =
               conn
               |> get(~p"/collections/#{collection.name}",
                 key: "foo:*:baz",
                 updated_after: DateTime.to_iso8601(after_insert)
               )
               |> json_response(200)

      assert %{
               "items" => [],
               "cursor" => nil
             } =
               conn
               |> get(~p"/collections/#{collection.name}",
                 key: "foo:*:baz",
                 updated_before: DateTime.to_iso8601(before_insert)
               )
               |> json_response(200)

      assert %{
               "items" => [
                 %{"key" => "foo:bar:baz", "value" => _},
                 %{"key" => "foo:moon:baz", "value" => _}
               ],
               "cursor" => nil
             } =
               conn
               |> get(~p"/collections/#{collection.name}",
                 key: "foo:*:baz",
                 updated_after: DateTime.to_iso8601(before_insert),
                 updated_before: DateTime.to_iso8601(after_insert)
               )
               |> json_response(200)
    end

    test "using creation filters", %{conn: conn} do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])

      before_insert = DateTime.utc_now()

      collection =
        insert(:collection,
          project: project,
          items: insert_list(3, :collection_item)
        )

      after_insert = DateTime.utc_now() |> DateTime.add(10, :millisecond)

      token = Lightning.Accounts.generate_api_token(user)

      conn = assign_bearer(conn, token)

      items = Enum.map(collection.items, &encode_decode/1)

      assert %{
               "items" => ^items,
               "cursor" => nil
             } =
               conn
               |> get(~p"/collections/#{collection.name}",
                 created_after: DateTime.to_iso8601(before_insert)
               )
               |> json_response(200)

      assert %{
               "items" => ^items,
               "cursor" => nil
             } =
               conn
               |> get(~p"/collections/#{collection.name}",
                 created_before: DateTime.to_iso8601(after_insert)
               )
               |> json_response(200)

      items = Enum.map(collection.items, &encode_decode/1)

      assert %{
               "items" => ^items,
               "cursor" => nil
             } =
               conn
               |> get(~p"/collections/#{collection.name}")
               |> json_response(200)
    end

    test "using update filters", %{conn: conn} do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])

      collection = insert(:collection, project: project)

      old_item =
        insert(:collection_item, collection: collection, key: "old-key")
        |> encode_decode()

      before_insert_list = DateTime.utc_now()

      items =
        insert_list(3, :collection_item, collection: collection)
        |> Enum.map(&encode_decode/1)

      after_insert = DateTime.utc_now() |> DateTime.add(10, :millisecond)

      token = Lightning.Accounts.generate_api_token(user)

      conn = assign_bearer(conn, token)

      assert conn
             |> get(~p"/collections/#{collection.name}",
               updated_after:
                 DateTime.to_date(before_insert_list) |> Date.to_iso8601()
             )
             |> json_response(400)

      assert %{
               "items" => ^items,
               "cursor" => nil
             } =
               conn
               |> get(~p"/collections/#{collection.name}",
                 updated_after: DateTime.to_iso8601(before_insert_list)
               )
               |> json_response(200)

      expected_items = [old_item | items]

      assert %{
               "items" => ^expected_items,
               "cursor" => nil
             } =
               conn
               |> get(~p"/collections/#{collection.name}",
                 updated_before: DateTime.to_iso8601(after_insert)
               )
               |> json_response(200)

      assert %{
               "items" => ^expected_items,
               "cursor" => nil
             } =
               conn
               |> get(~p"/collections/#{collection.name}")
               |> json_response(200)
    end

    test "up to the default limit", %{conn: conn} do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])

      collection =
        insert(:collection,
          project: project,
          items: insert_list(3, :collection_item)
        )

      token = Lightning.Accounts.generate_api_token(user)

      conn =
        conn
        |> assign_bearer(token)
        |> get(~p"/collections/#{collection.name}")

      assert conn.state == :chunked

      items =
        collection.items
        |> Enum.map(&encode_decode/1)

      assert json_response(conn, 200) == %{
               "items" => items,
               "cursor" => nil
             }

      # Insert more to bring the total to the stream limit
      items =
        Enum.concat(
          items,
          insert_list(
            @default_stream_limit - length(collection.items),
            :collection_item,
            collection: collection
          )
          |> Enum.map(&encode_decode/1)
        )

      conn = conn |> get(~p"/collections/#{collection.name}")

      assert json_response(conn, 200) == %{"items" => items, "cursor" => nil}
    end

    test "up to a limit from params", %{
      conn: conn
    } do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])
      limit = @max_database_limit + 10

      collection =
        insert(:collection,
          project: project,
          items: insert_list(limit + 1, :collection_item)
        )

      all_items =
        collection.items
        |> Enum.map(&encode_decode/1)

      expected_items =
        all_items |> Enum.take(limit)

      last_item =
        collection.items
        |> Enum.take(limit)
        |> List.last()

      token = Lightning.Accounts.generate_api_token(user)

      conn =
        conn
        |> assign_bearer(token)
        |> get(~p"/collections/#{collection.name}", limit: limit)

      assert conn.state == :chunked

      assert json_response(conn, 200) == %{
               "items" => expected_items,
               "cursor" => Base.encode64(to_string(last_item.id))
             }

      # Test for the existence of a cursor when the limit is less than the
      # database limit
      half_limit = (@max_database_limit / 2) |> floor()

      expected_items =
        all_items |> Enum.take(half_limit)

      last_item =
        collection.items
        |> Enum.take(half_limit)
        |> List.last()

      conn =
        conn
        |> get(~p"/collections/#{collection.name}",
          limit: half_limit
        )

      assert json_response(conn, 200) == %{
               "items" => expected_items,
               "cursor" => Base.encode64(to_string(last_item.id))
             }

      # Request everything, shouldn't be getting a cursor
      conn =
        conn |> get(~p"/collections/#{collection.name}", limit: limit + 1)

      assert json_response(conn, 200) == %{
               "items" => all_items,
               "cursor" => nil
             }
    end
  end

  describe "GET /collections/:name with cursors" do
    test "up to the default limit and returning a cursor", %{conn: conn} do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])
      collection = insert(:collection, project: project)

      items =
        insert_list(@default_stream_limit + 1, :collection_item,
          collection: collection
        )

      token = Lightning.Accounts.generate_api_token(user)

      conn =
        conn
        |> assign_bearer(token)
        |> get(~p"/collections/#{collection.name}")

      assert conn.state == :chunked

      expected_items = Enum.take(items, @default_stream_limit)
      last_item = List.last(expected_items)

      assert %{
               "items" => items,
               "cursor" => cursor
             } = json_response(conn, 200)

      assert items ==
               expected_items
               |> Enum.map(&encode_decode/1)

      assert cursor == Base.encode64(to_string(last_item.id))
    end

    test "up to the limit from a cursor returning a cursor", %{conn: conn} do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])
      collection = insert(:collection, project: project)
      limit = 100

      all_items =
        insert_list(2 * limit + 1, :collection_item, collection: collection)
        |> Enum.map(&encode_decode/1)

      token = Lightning.Accounts.generate_api_token(user)

      conn = assign_bearer(conn, token)

      conn =
        conn
        |> assign_bearer(token)
        |> get(~p"/collections/#{collection.name}", limit: limit)

      assert conn.state == :chunked

      expected_items = all_items |> Enum.take(limit)

      assert %{
               "items" => ^expected_items,
               "cursor" => cursor
             } = json_response(conn, 200)

      conn =
        conn
        |> get(~p"/collections/#{collection.name}", cursor: cursor, limit: limit)

      assert conn.state == :chunked

      expected_items = all_items |> Enum.drop(limit) |> Enum.take(limit)

      assert %{
               "items" => ^expected_items,
               "cursor" => cursor
             } = json_response(conn, 200)

      %{id: id} =
        Repo.get_by(Collections.Item,
          collection_id: collection.id,
          key: List.last(expected_items)["key"]
        )

      assert {^id, ""} =
               cursor |> Base.decode64!() |> Integer.parse()
    end

    test "up exactly to the limit from a cursor", %{conn: conn} do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])
      collection = insert(:collection, project: project)
      limit = @default_stream_limit

      all_items =
        insert_list(2 * limit, :collection_item, collection: collection)

      token = Lightning.Accounts.generate_api_token(user)

      conn = assign_bearer(conn, token)

      assert %{state: :chunked} =
               conn =
               get(conn, ~p"/collections/#{collection.name}", limit: limit)

      expected_items =
        all_items
        |> Enum.take(limit)
        |> Enum.map(&encode_decode/1)

      assert %{
               "items" => response_items,
               "cursor" => cursor
             } = json_response(conn, 200)

      assert response_items == expected_items

      assert %{state: :chunked} =
               conn =
               get(conn, ~p"/collections/#{collection.name}",
                 cursor: cursor,
                 limit: limit
               )

      expected_items =
        all_items
        |> Enum.drop(limit)
        |> Enum.map(&encode_decode/1)

      assert %{
               "items" => ^expected_items,
               "cursor" => nil
             } = json_response(conn, 200)
    end
  end

  describe "GET /download/collections/:project_id/:name" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    setup %{conn: conn} do
      {:ok, conn: put_req_header(conn, "accept", "text/html,*/*")}
    end

    test "downloads collection items as JSON array", %{
      conn: conn,
      project: project
    } do
      collection = insert(:collection, project: project)

      insert(:collection_item,
        collection: collection,
        key: "key-1",
        value: ~s({"name": "Alice"})
      )

      insert(:collection_item,
        collection: collection,
        key: "key-2",
        value: ~s({"name": "Bob"})
      )

      response =
        get(conn, ~p"/download/collections/#{project.id}/#{collection.name}")

      assert response.status == 200

      assert {"content-type", "application/json; charset=utf-8"} in response.resp_headers

      assert Enum.any?(response.resp_headers, fn
               {"content-disposition", value} ->
                 String.contains?(value, "attachment") and
                   String.contains?(value, collection.name)

               _ ->
                 false
             end)

      items = Jason.decode!(response.resp_body)
      assert length(items) == 2
      assert Enum.any?(items, fn item -> item["key"] == "key-1" end)
      assert Enum.any?(items, fn item -> item["key"] == "key-2" end)
    end

    test "downloads empty collection as empty JSON array", %{
      conn: conn,
      project: project
    } do
      collection = insert(:collection, project: project)

      response =
        get(conn, ~p"/download/collections/#{project.id}/#{collection.name}")

      assert response.status == 200
      assert Jason.decode!(response.resp_body) == []
    end

    test "returns 401 when user is not a project member", %{conn: conn} do
      other_project = insert(:project)
      collection = insert(:collection, project: other_project)

      response =
        get(
          conn,
          ~p"/download/collections/#{other_project.id}/#{collection.name}"
        )

      assert response.status == 401
    end

    test "returns 404 for non-existent collection", %{
      conn: conn,
      project: project
    } do
      response = get(conn, ~p"/download/collections/#{project.id}/non-existent")

      assert response.status == 404
    end
  end

  describe "malformed request bodies" do
    setup %{conn: conn} do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])
      collection = insert(:collection, project: project)
      token = Lightning.Accounts.generate_api_token(user)
      conn = assign_bearer(conn, token)
      {:ok, conn: conn, project: project, collection: collection}
    end

    test "PUT with no value returns 422", %{conn: conn, collection: collection} do
      conn = put(conn, ~p"/collections/#{collection.name}/some-key", %{})

      assert json_response(conn, 422)["error"] =~ "Missing required field: value"
    end

    test "POST with no items returns 422", %{conn: conn, collection: collection} do
      conn = post(conn, ~p"/collections/#{collection.name}", %{})

      assert json_response(conn, 422)["error"] =~ "Missing required field: items"
    end
  end

  describe "ambiguous name without ?project_id" do
    setup %{conn: conn} do
      user = insert(:user)
      project_1 = insert(:project, project_users: [%{user: user}])
      project_2 = insert(:project, project_users: [%{user: user}])
      name = "shared-collection"
      insert(:collection, name: name, project: project_1)
      insert(:collection, name: name, project: project_2)
      token = Lightning.Accounts.generate_api_token(user)
      conn = assign_bearer(conn, token)
      {:ok, conn: conn, name: name}
    end

    test "GET /:name returns 409", %{conn: conn, name: name} do
      conn = get(conn, ~p"/collections/#{name}")
      assert json_response(conn, 409)["error"] =~ "Add ?project_id="
    end

    test "GET /:name/:key returns 409", %{conn: conn, name: name} do
      conn = get(conn, ~p"/collections/#{name}/some-key")
      assert json_response(conn, 409)["error"] =~ "Add ?project_id="
    end

    test "PUT /:name/:key returns 409", %{conn: conn, name: name} do
      conn = put(conn, ~p"/collections/#{name}/some-key", value: "val")
      assert json_response(conn, 409)["error"] =~ "Add ?project_id="
    end

    test "POST /:name returns 409", %{conn: conn, name: name} do
      conn = post(conn, ~p"/collections/#{name}", items: [])
      assert json_response(conn, 409)["error"] =~ "Add ?project_id="
    end

    test "DELETE /:name/:key returns 409", %{conn: conn, name: name} do
      conn = delete(conn, ~p"/collections/#{name}/some-key")
      assert json_response(conn, 409)["error"] =~ "Add ?project_id="
    end

    test "DELETE /:name returns 409", %{conn: conn, name: name} do
      conn = delete(conn, ~p"/collections/#{name}")
      assert json_response(conn, 409)["error"] =~ "Add ?project_id="
    end
  end

  describe "?project_id=<uuid> query param" do
    setup %{conn: conn} do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])

      collection =
        insert(:collection,
          project: project,
          items: [%{key: "foo", value: "bar"}]
        )

      token = Lightning.Accounts.generate_api_token(user)
      conn = assign_bearer(conn, token)
      {:ok, conn: conn, project: project, collection: collection}
    end

    test "GET /:name/:key returns the item", %{
      conn: conn,
      project: project,
      collection: collection
    } do
      item = hd(collection.items)

      conn =
        get(
          conn,
          ~p"/collections/#{collection.name}/foo?project_id=#{project.id}"
        )

      assert json_response(conn, 200) == %{
               "key" => item.key,
               "value" => item.value,
               "created" => DateTime.to_iso8601(item.inserted_at),
               "updated" => DateTime.to_iso8601(item.updated_at)
             }
    end

    test "GET /:name/:key returns 204 when item not found", %{
      conn: conn,
      project: project,
      collection: collection
    } do
      conn =
        get(
          conn,
          ~p"/collections/#{collection.name}/nonexistent?project_id=#{project.id}"
        )

      assert response(conn, 204) == ""
    end

    test "GET /:name/:key returns 404 when collection not found", %{
      conn: conn,
      project: project
    } do
      conn =
        get(
          conn,
          ~p"/collections/nonexistent-collection/foo?project_id=#{project.id}"
        )

      assert json_response(conn, 404)
    end

    test "GET /:name streams items scoped by project", %{
      conn: conn,
      project: project,
      collection: collection
    } do
      conn =
        get(conn, ~p"/collections/#{collection.name}?project_id=#{project.id}")

      body = json_response(conn, 200)
      assert length(body["items"]) == 1
      assert hd(body["items"])["key"] == "foo"
    end

    test "PUT /:name/:key upserts an item", %{
      conn: conn,
      project: project,
      collection: collection
    } do
      conn =
        put(
          conn,
          ~p"/collections/#{collection.name}/new-key?project_id=#{project.id}",
          value: "new-val"
        )

      assert json_response(conn, 200) == %{"upserted" => 1, "error" => nil}
    end

    test "POST /:name upserts multiple items", %{
      conn: conn,
      project: project,
      collection: collection
    } do
      conn =
        post(
          conn,
          ~p"/collections/#{collection.name}?project_id=#{project.id}",
          items: [%{key: "a", value: "1"}, %{key: "b", value: "2"}]
        )

      assert json_response(conn, 200) == %{"upserted" => 2, "error" => nil}
    end

    test "DELETE /:name/:key deletes an item", %{
      conn: conn,
      project: project,
      collection: collection
    } do
      conn =
        delete(
          conn,
          ~p"/collections/#{collection.name}/foo?project_id=#{project.id}"
        )

      assert json_response(conn, 200) == %{
               "key" => "foo",
               "deleted" => 1,
               "error" => nil
             }
    end

    test "DELETE /:name deletes all items", %{
      conn: conn,
      project: project,
      collection: collection
    } do
      conn =
        delete(
          conn,
          ~p"/collections/#{collection.name}?project_id=#{project.id}"
        )

      assert json_response(conn, 200)["deleted"] == 1
    end

    test "returns 401 when user does not have access to the project", %{
      conn: conn
    } do
      other_project = insert(:project)
      other_collection = insert(:collection, project: other_project)

      conn =
        get(
          conn,
          ~p"/collections/#{other_collection.name}/foo?project_id=#{other_project.id}"
        )

      assert json_response(conn, 401)
    end

    test "resolves correctly when same name exists in multiple projects", %{
      conn: conn,
      project: project,
      collection: collection
    } do
      other_project = insert(:project, project_users: [])
      insert(:collection, name: collection.name, project: other_project)

      conn =
        get(
          conn,
          ~p"/collections/#{collection.name}/foo?project_id=#{project.id}"
        )

      assert json_response(conn, 200)["key"] == "foo"
    end

    test "returns 400 when project_id is not a valid UUID", %{
      conn: conn,
      collection: collection
    } do
      conn =
        get(conn, ~p"/collections/#{collection.name}?project_id=not-a-uuid")

      assert response(conn, 400)
    end

    test "with a valid run token, can access own project's collection", %{
      conn: conn,
      project: project,
      collection: collection
    } do
      workflow = insert(:simple_workflow, project: project)

      workorder =
        insert(:workorder, workflow: workflow, dataclip: insert(:dataclip))

      run =
        insert(:run,
          work_order: workorder,
          dataclip: workorder.dataclip,
          starting_trigger: hd(workflow.triggers)
        )

      token = Lightning.Workers.generate_run_token(run)

      conn =
        conn
        |> assign_bearer(token)
        |> get(~p"/collections/#{collection.name}/foo?project_id=#{project.id}")

      assert json_response(conn, 200)["key"] == "foo"
    end

    test "with a valid run token, can write to own project's collection", %{
      conn: conn,
      project: project,
      collection: collection
    } do
      workflow = insert(:simple_workflow, project: project)

      workorder =
        insert(:workorder, workflow: workflow, dataclip: insert(:dataclip))

      run =
        insert(:run,
          work_order: workorder,
          dataclip: workorder.dataclip,
          starting_trigger: hd(workflow.triggers)
        )

      token = Lightning.Workers.generate_run_token(run)

      conn =
        conn
        |> assign_bearer(token)
        |> put(
          ~p"/collections/#{collection.name}/new-key?project_id=#{project.id}",
          value: "new-val"
        )

      assert json_response(conn, 200) == %{"upserted" => 1, "error" => nil}
    end

    test "with a run token, cannot access a different project's collection", %{
      conn: conn
    } do
      other_project = insert(:project)
      other_collection = insert(:collection, project: other_project)

      workflow = insert(:simple_workflow)

      workorder =
        insert(:workorder, workflow: workflow, dataclip: insert(:dataclip))

      run =
        insert(:run,
          work_order: workorder,
          dataclip: workorder.dataclip,
          starting_trigger: hd(workflow.triggers)
        )

      token = Lightning.Workers.generate_run_token(run)

      conn =
        conn
        |> assign_bearer(token)
        |> get(
          ~p"/collections/#{other_collection.name}/foo?project_id=#{other_project.id}"
        )

      assert json_response(conn, 401)
    end
  end

  defp encode_decode(item) do
    item
    |> Jason.encode!()
    |> Jason.decode!()
  end
end
