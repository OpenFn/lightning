defmodule LightningWeb.API.Collections.ListingTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import Lightning.ServiceAccountHelpers

  @url LightningWeb.Endpoint.url()

  defp project_with_owner do
    owner = insert(:user)
    project = insert(:project, project_users: [%{user: owner, role: :owner}])
    {owner, project}
  end

  defp entry(collection) do
    %{
      "id" => collection.id,
      "project_id" => collection.project_id,
      "name" => collection.name,
      "byte_size_sum" => collection.byte_size_sum
    }
  end

  defp links(path, query, page, last) do
    url = fn number ->
      "#{@url}#{path}?" <>
        Plug.Conn.Query.encode(
          Map.merge(query, %{"page" => number, "page_size" => 10})
        )
    end

    %{
      "self" => url.(page),
      "first" => url.(1),
      "last" => url.(last),
      "next" => if(page < last, do: url.(page + 1)),
      "prev" => if(page > 1, do: url.(page - 1))
    }
  end

  describe "listing a project's collections" do
    test "an owner on Lightning's own app lists them by name, each with its size",
         %{conn: conn} do
      {owner, project} = project_with_owner()
      visits = insert(:collection, project: project, name: "visits")

      patients =
        insert(:collection, project: project, name: "patients", byte_size_sum: 9)

      insert(:collection, name: "elsewhere")

      conn =
        conn
        |> session_conn(owner)
        |> get(~p"/api/projects/#{project.id}/collections")

      path = "/api/projects/#{project.id}/collections"

      assert json_response(conn, 200) == %{
               "data" => [entry(patients), entry(visits)],
               "links" => links(path, %{}, 1, 1)
             }
    end

    test "sorts by size, largest first, and keeps the sort in its links", %{
      conn: conn
    } do
      {conn, _account} = with_service_account(conn, ["collections:write"])
      project = insert(:project)
      small = insert(:collection, project: project, byte_size_sum: 10)
      large = insert(:collection, project: project, byte_size_sum: 2048)

      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/projects/#{project.id}/collections?sort=-byte_size_sum")

      path = "/api/projects/#{project.id}/collections"

      assert json_response(conn, 200) == %{
               "data" => [entry(large), entry(small)],
               "links" => links(path, %{"sort" => "-byte_size_sum"}, 1, 1)
             }
    end

    test "pages them", %{conn: conn} do
      {owner, project} = project_with_owner()

      [_a, b, _c] =
        for name <- ~w(a b c),
            do: insert(:collection, project: project, name: name)

      conn =
        conn
        |> session_conn(owner)
        |> get(~p"/api/projects/#{project.id}/collections?page=2&page_size=1")

      body = json_response(conn, 200)
      assert body["data"] == [entry(b)]

      assert body["links"]["next"] ==
               "#{@url}/api/projects/#{project.id}/collections?page=3&page_size=1"
    end

    test "answers 400 invalid_parameter for a sort it doesn't know", %{
      conn: conn
    } do
      {owner, project} = project_with_owner()

      conn
      |> session_conn(owner)
      |> get(~p"/api/projects/#{project.id}/collections?sort=inserted_at")
      |> assert_problem(400, :invalid_parameter, [
        %{
          "parameter" => "sort",
          "code" => "not_allowed",
          "detail" => "is invalid"
        }
      ])
    end
  end

  describe "listing every collection" do
    test "a superuser on Lightning's own app lists every project's, each with its project's name",
         %{conn: conn} do
      superuser = insert(:user, role: :superuser)
      first = insert(:project, name: "first")
      second = insert(:project, name: "second")
      b = insert(:collection, project: first, name: "b", byte_size_sum: 5)
      a = insert(:collection, project: second, name: "a")

      conn = conn |> session_conn(superuser) |> get(~p"/api/collections")

      assert json_response(conn, 200) == %{
               "data" => [
                 Map.put(entry(a), "project_name", "second"),
                 Map.put(entry(b), "project_name", "first")
               ],
               "links" => links("/api/collections", %{}, 1, 1)
             }
    end

    test "a service account with collections:write lists them, sorted as asked",
         %{conn: conn} do
      {conn, _account} = with_service_account(conn, ["collections:write"])
      small = insert(:collection, byte_size_sum: 1)
      large = insert(:collection, byte_size_sum: 100)

      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/collections?sort=-byte_size_sum&page_size=2")

      assert Enum.map(json_response(conn, 200)["data"], & &1["id"]) ==
               [large.id, small.id]
    end

    test "answers 400 invalid_parameter for a sort it doesn't know", %{
      conn: conn
    } do
      conn
      |> session_conn(insert(:user, role: :superuser))
      |> get(~p"/api/collections?sort=size")
      |> assert_problem(400, :invalid_parameter, [
        %{
          "parameter" => "sort",
          "code" => "not_allowed",
          "detail" => "is invalid"
        }
      ])
    end
  end

  describe "who may reach it" do
    test "a project's list is for its owners and admins and the service account; anyone else gets 403 whatever the project id",
         %{conn: conn} do
      [owner, admin, editor, viewer, stranger, short_of_mfa] =
        insert_list(6, :user)

      superuser = insert(:user, role: :superuser)

      project =
        insert(:project,
          project_users: [
            %{user: owner, role: :owner},
            %{user: admin, role: :admin},
            %{user: editor, role: :editor},
            %{user: viewer, role: :viewer}
          ]
        )

      mfa_project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: short_of_mfa, role: :owner}]
        )

      scheduled =
        insert(:project,
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second),
          project_users: [%{user: owner, role: :owner}]
        )

      {service_account, _account} =
        with_service_account(conn, ["collections:write"])

      service_account =
        put_req_header(service_account, "accept", "application/json")

      malformed = [not_a_uuid_entry(%{"path" => "project_id"})]

      refused =
        for {user, project_id} <-
              [
                {stranger, project.id},
                {editor, project.id},
                {viewer, project.id},
                {superuser, project.id},
                {short_of_mfa, mfa_project.id},
                {stranger, scheduled.id}
              ] ++
                for(
                  user <- [owner, stranger],
                  id <- [Ecto.UUID.generate(), "not-a-uuid"],
                  do: {user, id}
                ),
            do: {session_conn(conn, user), project_id, 403, :forbidden, []}

      instance_wide =
        for caller <- [session_conn(conn, superuser), service_account],
            {project_id, status, code, entries} <- [
              {Ecto.UUID.generate(), 404, :not_found, []},
              {"not-a-uuid", 400, :invalid_parameter, malformed}
            ],
            do: {caller, project_id, status, code, entries}

      scheduled_rows = [
        {session_conn(conn, owner), scheduled.id, 409, :scheduled_for_deletion,
         []}
      ]

      for {caller, project_id, status, code, entries} <-
            refused ++ instance_wide ++ scheduled_rows do
        caller
        |> get(~p"/api/projects/#{project_id}/collections")
        |> assert_problem(status, code, entries)
      end

      for user <- [owner, admin] do
        assert conn
               |> session_conn(user)
               |> get(~p"/api/projects/#{project.id}/collections")
               |> json_response(200)
      end
    end

    test "every project's list is for superusers and the service account; anyone else gets 403",
         %{conn: conn} do
      {owner, _project} = project_with_owner()

      for caller <- [
            session_conn(conn, owner),
            session_conn(conn, insert(:user, support_user: true)),
            conn
            |> put_req_header("accept", "application/json")
            |> assign_bearer(owner)
          ] do
        caller
        |> get(~p"/api/collections")
        |> assert_problem(403, :forbidden, [])
      end
    end
  end
end
