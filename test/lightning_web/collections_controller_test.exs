defmodule LightningWeb.API.CollectionsControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

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

      assert json_response(conn, 200) == []
    end

    test "with 10 results", %{conn: conn} do
      user = insert(:user)

      project =
        insert(:project, project_users: [%{user: user}])

      collection =
        insert(:collection,
          project: project,
          items: insert_list(65, :collection_item)
        )

      token = Lightning.Accounts.generate_api_token(user)

      conn =
        conn
        |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
        |> get(~p"/collections/#{collection.name}")

      assert conn.state == :chunked

      assert json_response(conn, 200) ==
               collection.items
               |> Enum.map(fn item ->
                 %{"key" => item.key, "value" => item.value}
               end)
    end
  end
end
