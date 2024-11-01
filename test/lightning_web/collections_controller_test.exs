defmodule LightningWeb.API.CollectionsControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  @stream_limit Application.compile_env!(
                  :lightning,
                  Lightning.CollectionsController
                )[
                  :stream_limit
                ]

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
               "value" => item.value
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

      assert json_response(conn, 204) == nil
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
        |> put(~p"/collections/#{collection.name}/foo", %{value: "qux2"})

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
        |> post(~p"/collections/misspelled-collection/baz", value: "qux")

      assert json_response(conn, 404) == %{"error" => "Not Found"}
    end
  end

  describe "POST /collections/:name" do
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
               "keys" => ["foo"],
               "deleted" => 1,
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

      conn =
        conn
        |> assign_bearer(token)
        |> get(~p"/collections/#{collection.name}?#{%{key: "foo:bar:*"}}")

      assert conn.state == :chunked

      assert %{
               "items" => [
                 %{"key" => "foo:bar:baz", "value" => _},
                 %{"key" => "foo:bar:baz:quux", "value" => _}
               ],
               "cursor" => nil
             } = json_response(conn, 200)

      conn =
        conn
        |> get(~p"/collections/#{collection.name}?#{%{key: "foo:*:baz"}}")

      assert %{
               "items" => [%{"key" => "foo:bar:baz", "value" => _}],
               "cursor" => nil
             } = json_response(conn, 200)
    end

    test "up exactly to the limit", %{conn: conn} do
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

      assert json_response(conn, 200) == %{
               "items" =>
                 Enum.map(
                   collection.items,
                   &%{"key" => &1.key, "value" => &1.value}
                 ),
               "cursor" => nil
             }
    end

    @tag :skip
    test "up to a custom limit", %{conn: conn} do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])

      collection =
        insert(:collection,
          project: project,
          items: insert_list(11, :collection_item)
        )

      token = Lightning.Accounts.generate_api_token(user)

      conn =
        conn
        |> assign_bearer(token)
        |> get(~p"/collections/#{collection.name}?limit=10")

      assert conn.state == :chunked

      items = Enum.take(collection.items, 10)
      last_item = List.last(items)

      assert json_response(conn, 200) == %{
               "items" =>
                 Enum.map(
                   items,
                   &%{"key" => &1.key, "value" => &1.value}
                 ),
               "cursor" =>
                 Base.encode64(DateTime.to_iso8601(last_item.inserted_at))
             }
    end
  end

  describe "GET /collections/:name with cursors" do
    test "up to the limit and returning a cursor", %{conn: conn} do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])
      collection = insert(:collection, project: project)

      items =
        insert_list(@stream_limit + 1, :collection_item,
          collection: collection,
          inserted_at: fn -> build(:timestamp, from: {-300, :microsecond}) end
        )

      token = Lightning.Accounts.generate_api_token(user)

      conn =
        conn
        |> assign_bearer(token)
        |> get(~p"/collections/#{collection.name}")

      assert conn.state == :chunked

      items = Enum.take(items, @stream_limit)
      last_item = List.last(items)

      assert json_response(conn, 200) == %{
               "items" =>
                 Enum.map(items, &%{"key" => &1.key, "value" => &1.value}),
               "cursor" =>
                 Base.encode64(DateTime.to_iso8601(last_item.inserted_at))
             }
    end

    test "up exactly to the limit from a cursor", %{conn: conn} do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])
      collection = insert(:collection, project: project)

      items =
        insert_list(100, :collection_item,
          collection: collection,
          inserted_at: fn -> build(:timestamp, from: {-300, :microsecond}) end
        )

      token = Lightning.Accounts.generate_api_token(user)

      cursor =
        items
        |> Enum.at(@stream_limit - 1)
        |> Map.get(:inserted_at)
        |> DateTime.to_iso8601()
        |> Base.encode64()

      conn =
        conn
        |> assign_bearer(token)
        |> get(~p"/collections/#{collection.name}", cursor: cursor)

      assert conn.state == :chunked

      items = Enum.drop(items, @stream_limit)

      assert json_response(conn, 200) == %{
               "items" =>
                 Enum.map(items, &%{"key" => &1.key, "value" => &1.value}),
               "cursor" => nil
             }
    end

    test "up to the limit from a cursor", %{conn: conn} do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])
      collection = insert(:collection, project: project)

      items =
        insert_list(101, :collection_item,
          collection: collection,
          inserted_at: fn -> build(:timestamp, from: {-300, :microsecond}) end
        )

      token = Lightning.Accounts.generate_api_token(user)

      cursor =
        items
        |> Enum.at(@stream_limit - 1)
        |> Map.get(:inserted_at)
        |> DateTime.to_iso8601()
        |> Base.encode64()

      conn =
        conn
        |> assign_bearer(token)
        |> get(~p"/collections/#{collection.name}", cursor: cursor)

      assert conn.state == :chunked

      items = items |> Enum.drop(@stream_limit) |> Enum.take(@stream_limit)
      last_item = Enum.at(items, @stream_limit - 1)

      assert json_response(conn, 200) == %{
               "items" =>
                 Enum.map(items, &%{"key" => &1.key, "value" => &1.value}),
               "cursor" =>
                 Base.encode64(DateTime.to_iso8601(last_item.inserted_at))
             }
    end
  end
end
