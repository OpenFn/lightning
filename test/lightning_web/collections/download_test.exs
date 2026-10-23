defmodule LightningWeb.CollectionsDownloadTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  describe "downloading a collection from the browser" do
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

      items =
        for {key, value} <- [
              {"key-1", ~s({"name": "Alice"})},
              {"key-2", ~s({"name": "Bob"})}
            ] do
          insert(:collection_item,
            collection: collection,
            key: key,
            value: value
          )
          |> Jason.encode!()
          |> Jason.decode!()
        end

      response =
        get(conn, ~p"/download/collections/#{project.id}/#{collection.name}")

      assert response.status == 200

      assert get_resp_header(response, "content-type") ==
               ["application/json; charset=utf-8"]

      assert get_resp_header(response, "content-disposition") ==
               [~s(attachment; filename="#{collection.name}.json")]

      assert Jason.decode!(response.resp_body) == items
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

    test "returns 400 when project_id is not a valid UUID", %{conn: conn} do
      response = get(conn, ~p"/download/collections/not-a-uuid/anything")

      assert response.status == 400
    end

    test "does not serve the payload to a locked-out account",
         %{conn: conn, user: user, project: project} do
      Mox.stub(Lightning.MockConfig, :check_flag?, fn
        :require_email_verification -> true
        flag -> Lightning.Config.API.check_flag?(flag)
      end)

      user
      |> Ecto.Changeset.change(
        confirmed_at: nil,
        inserted_at:
          DateTime.utc_now()
          |> Timex.shift(hours: -50)
          |> DateTime.truncate(:second)
      )
      |> Lightning.Repo.update!()

      collection = insert(:collection, project: project)

      insert(:collection_item,
        collection: collection,
        key: "key-1",
        value: ~s({"name": "Alice"})
      )

      response =
        get(conn, ~p"/download/collections/#{project.id}/#{collection.name}")

      assert redirected_to(response) == "/users/confirm-required"
      refute response.resp_body =~ "Alice"
    end
  end
end
