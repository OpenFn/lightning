defmodule LightningWeb.API.OauthClients.ListingTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiOauthClientsHelpers
  import Lightning.ServiceAccountHelpers

  @url LightningWeb.Endpoint.url()

  defp only_page(path) do
    page = "#{@url}#{path}?page=1&page_size=10"

    %{
      "self" => page,
      "first" => page,
      "last" => page,
      "next" => nil,
      "prev" => nil
    }
  end

  describe "listing your own" do
    test "a person on Lightning's own app lists their own clients and the global ones, by name, without secrets",
         %{conn: conn} do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user, role: :owner}])
      hidden = insert(:project)

      own = insert(:oauth_client, user: user, name: "b own")
      insert(:project_oauth_client, oauth_client: own, project: project)
      insert(:project_oauth_client, oauth_client: own, project: hidden)

      global = insert(:oauth_client, global: true, name: "a global")
      insert(:oauth_client, name: "someone else's")

      conn = conn |> session_conn(user) |> get(~p"/api/oauth_clients")

      assert json_response(conn, 200) == %{
               "data" => [
                 client_json(global, []),
                 client_json(own, [project.id])
               ],
               "links" => only_page("/api/oauth_clients")
             }

      refute conn.resp_body =~ "client-secret"
    end

    test "pages them", %{conn: conn} do
      user = insert(:user)

      [_a, b, _c] =
        for name <- ~w(a b c), do: insert(:oauth_client, user: user, name: name)

      conn =
        conn
        |> session_conn(user)
        |> get(~p"/api/oauth_clients?page=2&page_size=1")

      body = json_response(conn, 200)
      assert Enum.map(body["data"], & &1["id"]) == [b.id]

      assert body["links"]["next"] ==
               "#{@url}/api/oauth_clients?page=3&page_size=1"
    end

    test "the service account owns none, so it is refused with 403", %{
      conn: conn
    } do
      {conn, _account} = with_service_account(conn, ["credentials:write"])

      conn
      |> put_req_header("accept", "application/json")
      |> get(~p"/api/oauth_clients")
      |> assert_problem(403, :forbidden, [])
    end
  end

  describe "listing a project's" do
    test "any member lists the clients linked to the project and the global ones",
         %{conn: conn} do
      viewer = insert(:user)
      project = insert(:project, project_users: [%{user: viewer, role: :viewer}])

      linked = insert(:oauth_client, name: "linked")
      insert(:project_oauth_client, oauth_client: linked, project: project)
      global = insert(:oauth_client, global: true, name: "global")
      insert(:oauth_client, user: viewer, name: "own but unlinked")

      conn =
        conn
        |> session_conn(viewer)
        |> get(~p"/api/projects/#{project.id}/oauth_clients")

      assert json_response(conn, 200) == %{
               "data" => [
                 client_json(global, []),
                 client_json(linked, [project.id])
               ],
               "links" => only_page("/api/projects/#{project.id}/oauth_clients")
             }
    end

    test "a service account with credentials:write lists them", %{conn: conn} do
      {conn, _account} = with_service_account(conn, ["credentials:write"])
      project = insert(:project)
      linked = insert(:oauth_client)
      insert(:project_oauth_client, oauth_client: linked, project: project)

      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get(~p"/api/projects/#{project.id}/oauth_clients")

      assert [%{"id" => id, "project_ids" => [project_id]}] =
               json_response(conn, 200)["data"]

      assert {id, project_id} == {linked.id, project.id}
    end
  end

  describe "who may reach a project's list" do
    test "members and the service account list them; anyone else gets 403 whatever the project id",
         %{conn: conn} do
      [owner, stranger, short_of_mfa] = insert_list(3, :user)
      superuser = insert(:user, role: :superuser)
      project = insert(:project, project_users: [%{user: owner, role: :owner}])

      mfa_project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: short_of_mfa, role: :viewer}]
        )

      {service_account, _account} =
        with_service_account(conn, ["credentials:write"])

      service_account =
        put_req_header(service_account, "accept", "application/json")

      malformed = [not_a_uuid_entry(%{"path" => "project_id"})]

      rows =
        for(
          {user, project_id} <- [
            {stranger, project.id},
            {superuser, project.id},
            {short_of_mfa, mfa_project.id},
            {owner, Ecto.UUID.generate()},
            {owner, "not-a-uuid"}
          ],
          do: {session_conn(conn, user), project_id, 403, :forbidden, []}
        ) ++
          for caller <- [session_conn(conn, superuser), service_account],
              {project_id, status, code, entries} <- [
                {Ecto.UUID.generate(), 404, :not_found, []},
                {"not-a-uuid", 400, :invalid_parameter, malformed}
              ],
              do: {caller, project_id, status, code, entries}

      for {caller, project_id, status, code, entries} <- rows do
        caller
        |> get(~p"/api/projects/#{project_id}/oauth_clients")
        |> assert_problem(status, code, entries)
      end
    end
  end
end
