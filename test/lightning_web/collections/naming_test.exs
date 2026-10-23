defmodule LightningWeb.API.CollectionsNamingTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.ApiCollectionsHelpers

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  setup :member_with_collection

  describe "a bare name" do
    test "answers 404 for a collection the project hasn't got, on every route",
         %{conn: conn} do
      for request <- [
            &get(&1, ~p"/collections/misspelled-collection/foo"),
            &put(&1, ~p"/collections/misspelled-collection/baz", value: "qux"),
            &post(&1, ~p"/collections/misspelled-collection",
              items: [%{key: "baz", value: "qux"}]
            ),
            &delete(&1, ~p"/collections/misspelled-collection/foo")
          ] do
        assert_problem(request.(conn), 404, :not_found, [])
      end
    end

    test "answers 409 ambiguous_name when two of the member's projects have it, on every route",
         %{conn: conn, user: user, project: project} do
      other_project = insert(:project, project_users: [%{user: user}])
      name = "shared-collection"
      insert(:collection, name: name, project: project)
      insert(:collection, name: name, project: other_project)

      for request <- [
            &get(&1, ~p"/collections/#{name}"),
            &get(&1, ~p"/collections/#{name}/some-key"),
            &put(&1, ~p"/collections/#{name}/some-key", value: "val"),
            &post(&1, ~p"/collections/#{name}", items: []),
            &delete(&1, ~p"/collections/#{name}/some-key"),
            &delete(&1, ~p"/collections/#{name}")
          ] do
        assert_problem(request.(conn), 409, :ambiguous_name, [])
      end
    end

    test "a run token counts only its own project's collection", %{
      conn: conn,
      project: project,
      collection: collection
    } do
      insert(:collection_item, collection: collection, key: "foo", value: "bar")
      insert(:collection, name: collection.name, project: insert(:project))

      conn =
        conn
        |> assign_bearer(run_token(project))
        |> get(~p"/collections/#{collection.name}/foo")

      assert json_response(conn, 200)["key"] == "foo"
    end
  end

  describe "?project_id=<uuid>" do
    @describetag role: :owner

    setup %{collection: collection} do
      item =
        insert(:collection_item,
          collection: collection,
          key: "foo",
          value: "bar"
        )

      %{item: item}
    end

    test "reads one item", %{
      conn: conn,
      project: project,
      collection: collection,
      item: item
    } do
      conn =
        get(
          conn,
          ~p"/collections/#{collection.name}/foo?project_id=#{project.id}"
        )

      assert json_response(conn, 200) == %{
               "key" => "foo",
               "value" => "bar",
               "created" => DateTime.to_iso8601(item.inserted_at),
               "updated" => DateTime.to_iso8601(item.updated_at)
             }
    end

    test "answers 204 for a key the collection hasn't got", %{
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

    test "answers 404 for a collection the project hasn't got", %{
      conn: conn,
      project: project
    } do
      conn =
        get(
          conn,
          ~p"/collections/nonexistent-collection/foo?project_id=#{project.id}"
        )

      assert_problem(conn, 404, :not_found, [])
    end

    test "lists the project's items", %{
      conn: conn,
      project: project,
      collection: collection,
      item: item
    } do
      conn =
        get(conn, ~p"/collections/#{collection.name}?project_id=#{project.id}")

      assert json_response(conn, 200) == %{
               "items" => [
                 %{
                   "key" => "foo",
                   "value" => "bar",
                   "created" => DateTime.to_iso8601(item.inserted_at),
                   "updated" => DateTime.to_iso8601(item.updated_at)
                 }
               ],
               "cursor" => nil
             }
    end

    test "upserts an item", %{
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

    test "upserts many items", %{
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

    test "deletes an item", %{
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
               "deleted" => 1
             }
    end

    test "deletes every item", %{
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

    test "answers 404 for a project the member doesn't belong to", %{conn: conn} do
      other_project = insert(:project)
      other_collection = insert(:collection, project: other_project)

      conn =
        get(
          conn,
          ~p"/collections/#{other_collection.name}/foo?project_id=#{other_project.id}"
        )

      assert_problem(conn, 404, :not_found, [])
    end

    test "picks the project's collection when another project has the same name",
         %{conn: conn, project: project, collection: collection} do
      insert(:collection,
        name: collection.name,
        project: insert(:project, project_users: [])
      )

      conn =
        get(
          conn,
          ~p"/collections/#{collection.name}/foo?project_id=#{project.id}"
        )

      assert json_response(conn, 200)["key"] == "foo"
    end

    test "answers 404 for a project_id that is not a UUID", %{
      conn: conn,
      collection: collection
    } do
      conn =
        get(conn, ~p"/collections/#{collection.name}?project_id=not-a-uuid")

      assert_problem(conn, 404, :not_found, [])
    end

    test "lets a run token of the project read", %{
      conn: conn,
      project: project,
      collection: collection
    } do
      conn =
        conn
        |> assign_bearer(run_token(project))
        |> get(~p"/collections/#{collection.name}/foo?project_id=#{project.id}")

      assert json_response(conn, 200)["key"] == "foo"
    end

    test "lets a run token of the project write", %{
      conn: conn,
      project: project,
      collection: collection
    } do
      conn =
        conn
        |> assign_bearer(run_token(project))
        |> put(
          ~p"/collections/#{collection.name}/new-key?project_id=#{project.id}",
          value: "new-val"
        )

      assert json_response(conn, 200) == %{"upserted" => 1, "error" => nil}
    end
  end
end
