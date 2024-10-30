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
    # test "for a project they don't have access to"
    # test "with a token that has expired"

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

      conn = conn |> assign_bearer(token)
      conn = get(conn, ~p"/collections/#{collection.name}")
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

      conn = conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      conn = get(conn, ~p"/collections/#{collection.name}")
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "get" do
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
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
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
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
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
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/collections/#{collection.name}/some-unexisting-key")

      assert json_response(conn, 200) == nil
    end
  end

  describe "put" do
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
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
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
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
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
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/collections/misspelled-collection/baz", value: "qux")

      assert json_response(conn, 404) == %{"error" => "Not Found"}
    end
  end

  describe "put_all" do
    test "upserts multiple items", %{conn: conn} do
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
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
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
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
        |> post(~p"/collections/misspelled-collection", %{
          items: [%{key: "baz", value: "qux"}]
        })

      assert json_response(conn, 404) == %{"error" => "Not Found"}
    end
  end

  describe "delete" do
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
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
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
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
        |> delete(~p"/collections/misspelled-collection/foo")

      assert json_response(conn, 404) == %{"error" => "Not Found"}
    end
  end

  describe "stream_all" do
    test "with no results", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      collection = insert(:collection, project: project)

      token = Lightning.Accounts.generate_api_token(user)

      conn =
        conn
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/collections/#{collection.name}")

      assert json_response(conn, 200) == %{"items" => [], "cursor" => nil}
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
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
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
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
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
                 Base.encode64(DateTime.to_iso8601(last_item.updated_at))
             }
    end
  end

  test "up to the limit and returning a cursor", %{conn: conn} do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user}])
    collection = insert(:collection, project: project)
    begin = DateTime.utc_now()

    items =
      Enum.map(1..(@stream_limit + 1), fn i ->
        updated_at = DateTime.add(begin, i, :microsecond)
        insert(:collection_item, updated_at: updated_at, collection: collection)
      end)

    token = Lightning.Accounts.generate_api_token(user)

    conn =
      conn
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/collections/#{collection.name}")

    assert conn.state == :chunked

    items = Enum.take(items, @stream_limit)
    last_item = List.last(items)

    assert json_response(conn, 200) == %{
             "items" =>
               Enum.map(items, &%{"key" => &1.key, "value" => &1.value}),
             "cursor" => Base.encode64(DateTime.to_iso8601(last_item.updated_at))
           }
  end

  test "up exactly to the limit from a cursor", %{conn: conn} do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user}])
    collection = insert(:collection, project: project)
    begin = DateTime.utc_now()

    items =
      Enum.map(1..100, fn i ->
        updated_at = DateTime.add(begin, i, :microsecond)
        insert(:collection_item, updated_at: updated_at, collection: collection)
      end)

    token = Lightning.Accounts.generate_api_token(user)

    cursor =
      items
      |> Enum.at(@stream_limit - 1)
      |> Map.get(:updated_at)
      |> DateTime.to_iso8601()
      |> Base.encode64()

    conn =
      conn
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
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
    begin = DateTime.utc_now()

    items =
      Enum.map(1..101, fn i ->
        updated_at = DateTime.add(begin, i, :microsecond)
        insert(:collection_item, updated_at: updated_at, collection: collection)
      end)

    token = Lightning.Accounts.generate_api_token(user)

    cursor =
      items
      |> Enum.at(@stream_limit - 1)
      |> Map.get(:updated_at)
      |> DateTime.to_iso8601()
      |> Base.encode64()

    conn =
      conn
      |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      |> get(~p"/collections/#{collection.name}", cursor: cursor)

    assert conn.state == :chunked

    items = items |> Enum.drop(@stream_limit) |> Enum.take(@stream_limit)
    last_item = Enum.at(items, @stream_limit - 1)

    assert json_response(conn, 200) == %{
             "items" =>
               Enum.map(items, &%{"key" => &1.key, "value" => &1.value}),
             "cursor" => Base.encode64(DateTime.to_iso8601(last_item.updated_at))
           }
  end
end
