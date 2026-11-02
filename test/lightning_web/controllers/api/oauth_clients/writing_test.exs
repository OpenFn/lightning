defmodule LightningWeb.API.OauthClients.WritingTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiOauthClientsHelpers
  import Lightning.RaceHelpers
  import Lightning.ServiceAccountHelpers

  alias Lightning.Credentials.OauthClient
  alias Lightning.Credentials.OauthClientAudit
  alias Lightning.Repo

  defp entry(pointer, code, detail),
    do: %{"pointer" => pointer, "code" => code, "detail" => detail}

  defp events(client_id) do
    Repo.all(
      from a in OauthClientAudit.base_query(),
        where: a.item_id == ^client_id,
        select: a.event,
        order_by: a.inserted_at
    )
  end

  defp editor_of_project(_context) do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :editor}])
    %{user: user, project: project}
  end

  describe "creating" do
    setup :editor_of_project

    test "a person on Lightning's own app creates a client under the path id, owned by them and linked to a project",
         %{conn: conn, user: user, project: project} do
      id = Ecto.UUID.generate()

      conn =
        conn
        |> session_conn(user)
        |> put_client(id, client_body(%{"project_ids" => [project.id]}))

      client = Repo.get!(OauthClient, id)

      assert json_response(conn, 201) == %{
               "data" => client_json(client, [project.id])
             }

      assert %{user_id: user_id, client_secret: "s3cr3t-never-rendered"} = client
      assert user_id == user.id
      refute conn.resp_body =~ "s3cr3t"
      assert linked_project_ids(id) == [project.id]
      assert Enum.sort(events(id)) == ["added_to_project", "created"]
    end

    test "a superuser may make a client global", %{conn: conn} do
      id = Ecto.UUID.generate()

      conn =
        conn
        |> session_conn(insert(:user, role: :superuser))
        |> put_client(id, client_body(%{"global" => true}))

      assert json_response(conn, 201)["data"]["global"] == true
      assert Repo.get!(OauthClient, id).global
    end

    test "the service account can't own a client, so it is refused with 403", %{
      conn: conn
    } do
      {conn, _account} = with_service_account(conn, ["credentials:write"])
      id = Ecto.UUID.generate()

      for path_id <- [id, "not-a-uuid"] do
        conn
        |> put_req_header("accept", "application/json")
        |> put_client(path_id, client_body())
        |> assert_problem(403, :forbidden, [])
      end

      refute Repo.get(OauthClient, id)
    end
  end

  describe "replacing" do
    setup :editor_of_project

    test "the owner replaces every field, keeps the secret when it is left out, and sets the links to exactly those sent",
         %{conn: conn, user: user, project: project} do
      dropped = insert(:project, project_users: [%{user: user, role: :editor}])
      client = insert(:oauth_client, user: user, client_secret: "kept")
      insert(:project_oauth_client, oauth_client: client, project: dropped)

      body =
        client_body(%{"name" => "Renamed", "project_ids" => [project.id]})
        |> Map.delete("client_secret")

      conn = conn |> session_conn(user) |> put_client(client.id, body)

      replaced = Repo.get!(OauthClient, client.id)

      assert json_response(conn, 200) == %{
               "data" => client_json(replaced, [project.id])
             }

      assert %{
               name: "Renamed",
               client_secret: "kept",
               revocation_endpoint: nil,
               scopes_doc_url: nil
             } = replaced

      assert linked_project_ids(client.id) == [project.id]

      assert Enum.sort(events(client.id)) ==
               ["added_to_project", "removed_from_project", "updated"]
    end

    test "sending what is stored answers 200 and records nothing", %{
      conn: conn,
      user: user
    } do
      client = insert(:oauth_client, user: user)

      body =
        client
        |> Map.take([
          :name,
          :client_id,
          :authorization_endpoint,
          :token_endpoint,
          :revocation_endpoint,
          :userinfo_endpoint,
          :introspection_endpoint,
          :scopes_doc_url,
          :mandatory_scopes,
          :optional_scopes,
          :global
        ])
        |> Map.new(fn {key, value} -> {Atom.to_string(key), value} end)

      conn = conn |> session_conn(user) |> put_client(client.id, body)

      assert json_response(conn, 200)["data"]["name"] == client.name
      assert events(client.id) == []
    end
  end

  describe "refusing a body" do
    setup :editor_of_project

    test "refuses a body it cannot take with one 422, each error at its key",
         %{conn: conn, user: user, project: project} do
      viewing = insert(:project, project_users: [%{user: user, role: :viewer}])
      conn = session_conn(conn, user)

      for {body, entries} <- [
            {%{},
             [
               entry("#/authorization_endpoint", "required", "can't be blank"),
               entry("#/client_id", "required", "can't be blank"),
               entry("#/client_secret", "required", "can't be blank"),
               entry("#/name", "required", "can't be blank"),
               entry("#/token_endpoint", "required", "can't be blank")
             ]},
            {client_body(%{"token_endpoint" => "ftp://example.com"}),
             [
               entry(
                 "#/token_endpoint",
                 "format",
                 "must be either a http or https URL"
               )
             ]},
            {client_body(%{"global" => true}),
             [
               entry(
                 "#/global",
                 "not_allowed",
                 "can only be changed by a superuser"
               )
             ]},
            {client_body(%{
               "project_ids" => [
                 project.id,
                 viewing.id,
                 insert(:project).id,
                 "not-a-uuid",
                 7
               ]
             }),
             [
               entry(
                 "#/project_ids/1",
                 "no_access",
                 "you may not link an OAuth client to this project"
               ),
               entry(
                 "#/project_ids/2",
                 "not_found",
                 "names nothing you can see"
               ),
               entry(
                 "#/project_ids/3",
                 "not_found",
                 "names nothing you can see"
               ),
               entry("#/project_ids/4", "type", "is invalid")
             ]},
            {client_body(%{"project_ids" => "all"}),
             [entry("#/project_ids", "type", "is invalid")]},
            {client_body(%{"user_id" => user.id, "id" => Ecto.UUID.generate()}),
             [
               entry("#/user_id", "unknown_key", "is not accepted"),
               entry("#/id", "mismatch", "does not match the id in the path")
             ]}
          ] do
        id = Ecto.UUID.generate()

        conn
        |> put_client(id, body)
        |> assert_problem(422, :invalid, entries)

        refute Repo.get(OauthClient, id)
      end
    end

    test "answers 400 malformed for a body that is not a JSON object", %{
      conn: conn,
      user: user
    } do
      conn
      |> session_conn(user)
      |> put_client(Ecto.UUID.generate(), ["x"])
      |> assert_problem(400, :malformed, [])
    end
  end

  describe "deleting" do
    test "the owner deletes a client, and credentials that used it stay without one",
         %{conn: conn} do
      user = insert(:user)
      client = insert(:oauth_client, user: user)
      insert(:project_oauth_client, oauth_client: client)

      credential =
        insert(:credential, user: user, schema: "oauth", oauth_client: client)

      conn = conn |> session_conn(user) |> delete_client(client.id)

      assert response(conn, 204) == ""
      refute Repo.get(OauthClient, client.id)
      assert Repo.reload!(credential).oauth_client_id == nil
      assert "deleted" in events(client.id)
    end
  end

  describe "who may reach it" do
    test "only the owner may replace or delete a client; anyone else gets 403 for every id",
         %{conn: conn} do
      owner = insert(:user)
      client = insert(:oauth_client, user: owner)
      global = insert(:oauth_client, global: true)

      {service_account, _account} =
        with_service_account(conn, ["credentials:write"])

      service_account =
        put_req_header(service_account, "accept", "application/json")

      others = [
        session_conn(conn, insert(:user)),
        session_conn(conn, insert(:user, role: :superuser)),
        service_account
      ]

      for caller <- others, id <- [client.id, global.id] do
        caller
        |> put_client(id, client_body())
        |> assert_problem(403, :forbidden, [])
      end

      for caller <- [session_conn(conn, owner) | others],
          id <- [global.id, Ecto.UUID.generate(), "not-a-uuid"] do
        caller |> delete_client(id) |> assert_problem(403, :forbidden, [])
      end

      for caller <- others do
        caller |> delete_client(client.id) |> assert_problem(403, :forbidden, [])
      end

      session_conn(conn, owner)
      |> put_client("not-a-uuid", client_body())
      |> assert_problem(400, :invalid_parameter, [
        not_a_uuid_entry(%{"path" => "id"})
      ])

      assert Repo.reload!(client).name == client.name
      assert Repo.get(OauthClient, global.id)
    end
  end

  describe "stale writes" do
    test "a client another request deletes mid-replace answers 409 concurrent_edit",
         %{conn: conn} do
      owner = insert(:user)
      client = insert(:oauth_client, user: owner)

      after_first_query("oauth_clients", client.id, fn id ->
        Repo.query!("DELETE FROM oauth_clients WHERE id = $1", [id])
      end)

      conn
      |> session_conn(owner)
      |> put_client(client.id, client_body())
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.get(OauthClient, client.id)
    end

    test "a client another request deletes mid-delete answers 409 concurrent_edit",
         %{conn: conn} do
      owner = insert(:user)
      client = insert(:oauth_client, user: owner)

      after_first_query("oauth_clients", client.id, fn id ->
        Repo.query!("DELETE FROM oauth_clients WHERE id = $1", [id])
      end)

      conn
      |> session_conn(owner)
      |> delete_client(client.id)
      |> assert_problem(409, :concurrent_edit, [])
    end
  end
end
