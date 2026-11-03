defmodule LightningWeb.API.KeychainCredentials.ListingTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiKeychainHelpers
  import Lightning.ServiceAccountHelpers

  @url LightningWeb.Endpoint.url()

  describe "listing" do
    test "any member on Lightning's own app lists the project's keychain credentials by name",
         %{conn: conn} do
      viewer = insert(:user)
      creator = insert(:user, email: "ada@example.com")

      project =
        insert(:project, project_users: [%{user: viewer, role: :viewer}])

      credential = insert(:credential, name: "Acme DHIS2")
      insert(:project_credential, project: project, credential: credential)

      second =
        insert(:keychain_credential,
          project: project,
          created_by: creator,
          name: "Per-district",
          path: "$.district",
          default_credential: credential
        )

      first =
        insert(:keychain_credential,
          project: project,
          created_by: creator,
          name: "by facility"
        )

      insert(:keychain_credential, name: "elsewhere")

      conn =
        conn
        |> session_conn(viewer)
        |> get(~p"/api/projects/#{project.id}/keychain_credentials")

      path = "/api/projects/#{project.id}/keychain_credentials"
      page = "#{@url}#{path}?page=1&page_size=10"

      assert json_response(conn, 200) == %{
               "data" => [keychain_json(first), keychain_json(second)],
               "links" => %{
                 "self" => page,
                 "first" => page,
                 "last" => page,
                 "next" => nil,
                 "prev" => nil
               }
             }

      assert [_, %{"default_credential_name" => "Acme DHIS2"}] =
               json_response(conn, 200)["data"]
    end

    test "pages them", %{conn: conn} do
      {conn, _account} = with_service_account(conn, ["credentials:write"])
      project = insert(:project)

      [_a, b, _c] =
        for name <- ~w(a b c),
            do: insert(:keychain_credential, project: project, name: name)

      conn =
        conn
        |> put_req_header("accept", "application/json")
        |> get(
          ~p"/api/projects/#{project.id}/keychain_credentials?page=2&page_size=1"
        )

      body = json_response(conn, 200)
      assert Enum.map(body["data"], & &1["id"]) == [b.id]

      assert body["links"]["prev"] ==
               "#{@url}/api/projects/#{project.id}/keychain_credentials?page=1&page_size=1"
    end
  end

  describe "who may reach it" do
    test "members and the service account list them; anyone else gets 403 whatever the project id",
         %{conn: conn} do
      [owner, viewer, stranger, short_of_mfa] = insert_list(4, :user)
      superuser = insert(:user, role: :superuser)

      project =
        insert(:project,
          project_users: [
            %{user: owner, role: :owner},
            %{user: viewer, role: :viewer}
          ]
        )

      mfa_project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: short_of_mfa, role: :viewer}]
        )

      scheduled =
        insert(:project,
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second),
          project_users: [%{user: owner, role: :owner}]
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
            {stranger, scheduled.id},
            {owner, Ecto.UUID.generate()},
            {owner, "not-a-uuid"}
          ],
          do: {session_conn(conn, user), project_id, 403, :forbidden, []}
        ) ++
          for(
            caller <- [session_conn(conn, superuser), service_account],
            {project_id, status, code, entries} <- [
              {Ecto.UUID.generate(), 404, :not_found, []},
              {"not-a-uuid", 400, :invalid_parameter, malformed}
            ],
            do: {caller, project_id, status, code, entries}
          ) ++
          [
            {session_conn(conn, owner), scheduled.id, 409,
             :scheduled_for_deletion, []}
          ]

      for {caller, project_id, status, code, entries} <- rows do
        caller
        |> get(~p"/api/projects/#{project_id}/keychain_credentials")
        |> assert_problem(status, code, entries)
      end

      for caller <- [session_conn(conn, viewer), service_account] do
        assert caller
               |> get(~p"/api/projects/#{project.id}/keychain_credentials")
               |> json_response(200)
      end
    end
  end
end
