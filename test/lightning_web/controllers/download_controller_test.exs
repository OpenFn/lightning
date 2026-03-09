defmodule LightningWeb.DownloadControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  describe "GET /downloads/yaml" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    test "correctly renders a project yaml", %{conn: conn, project: project} do
      response =
        conn
        |> get(~p"/download/yaml?#{%{id: project.id}}")

      assert response.status == 200
    end

    test "renders a 404? when the user isn't authorized", %{conn: conn} do
      p = insert(:project)

      response =
        conn
        |> get(~p"/download/yaml?#{%{id: p.id}}")

      assert response.status == 401
    end
  end

  describe "GET /download/collection" do
    setup :register_and_log_in_user
    setup :create_project_for_current_user

    test "downloads collection items as JSON", %{
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
        conn
        |> get(
          ~p"/download/collection?#{%{project_id: project.id, name: collection.name}}"
        )

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
        conn
        |> get(
          ~p"/download/collection?#{%{project_id: project.id, name: collection.name}}"
        )

      assert response.status == 200
      assert Jason.decode!(response.resp_body) == []
    end

    test "returns 401 when user is not a project member", %{conn: conn} do
      other_project = insert(:project)
      collection = insert(:collection, project: other_project)

      response =
        conn
        |> get(
          ~p"/download/collection?#{%{project_id: other_project.id, name: collection.name}}"
        )

      assert response.status == 401
    end

    test "returns 404 for non-existent collection", %{
      conn: conn,
      project: project
    } do
      response =
        conn
        |> get(
          ~p"/download/collection?#{%{project_id: project.id, name: "non-existent"}}"
        )

      assert response.status == 404
    end

    test "returns 404 when collection belongs to a different project", %{
      conn: conn,
      project: project
    } do
      other_project = insert(:project)
      collection = insert(:collection, project: other_project)

      # User has access to their project but collection belongs to other_project
      response =
        conn
        |> get(
          ~p"/download/collection?#{%{project_id: project.id, name: collection.name}}"
        )

      assert response.status == 404
    end
  end

  describe "when not logged in" do
    test "redirects when you are not logged in", %{conn: conn} do
      response =
        conn
        |> get("/download/yaml?id=#{Ecto.UUID.generate()}")

      assert response.status == 302
      assert response.resp_headers
      assert {"location", "/users/log_in"} in response.resp_headers
    end

    test "redirects for collection download when not logged in", %{conn: conn} do
      response =
        conn
        |> get(
          "/download/collection?project_id=#{Ecto.UUID.generate()}&name=test"
        )

      assert response.status == 302
      assert {"location", "/users/log_in"} in response.resp_headers
    end
  end
end
