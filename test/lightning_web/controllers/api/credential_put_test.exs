defmodule LightningWeb.API.CredentialPutTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  alias Lightning.Credentials
  alias Lightning.Credentials.Credential
  alias Lightning.Repo

  @secret "s3cr3t-never-rendered"

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  defp put_credential(conn, id, body) do
    conn
    |> put_req_header("content-type", "application/json")
    |> put(~p"/api/credentials/#{id}", Jason.encode!(body))
  end

  defp with_pat(conn, user) do
    assign_bearer(conn, Lightning.Accounts.generate_api_token(user))
  end

  defp credential_body(attrs) do
    Map.merge(
      %{
        "name" => "Acme DHIS2",
        "schema" => "raw",
        "credential_bodies" => [
          %{"name" => "main", "body" => %{"password" => @secret}}
        ]
      },
      attrs
    )
  end

  defp links(project_ids),
    do: Enum.map(project_ids, &%{"project_id" => &1})

  defp main_body(credential_id),
    do: Credentials.get_credential_body(credential_id, "main").body

  defp linked_project_ids(response) do
    response["credential"]["project_credentials"]
    |> Enum.map(& &1["project_id"])
    |> Enum.sort()
  end

  # A credential with a staging body beside its main one, linked to `project`.
  defp existing_credential(owner, project) do
    {:ok, credential} =
      Credentials.create_credential(
        %{
          "name" => "Acme DHIS2",
          "schema" => "raw",
          "user_id" => owner.id,
          "credential_bodies" => [
            %{"name" => "main", "body" => %{"password" => "old"}},
            %{"name" => "staging", "body" => %{"password" => "staging"}}
          ],
          "project_credentials" => [%{"project_id" => project.id}]
        },
        owner
      )

    credential
  end

  describe "PUT, for a service account with credentials:write" do
    setup %{conn: conn} do
      {conn, account} = with_service_account(conn, ["credentials:write"])
      %{conn: conn, account: account}
    end

    test "creates the credential under the path id for the owner it names", %{
      conn: conn
    } do
      owner = insert(:user, email: "alice@example.com")
      [project_a, project_b] = insert_pair(:project)
      id = Ecto.UUID.generate()

      conn =
        put_credential(
          conn,
          id,
          credential_body(%{
            "owner" => "ALICE@example.com",
            "project_credentials" => links([project_a.id, project_b.id])
          })
        )

      response = json_response(conn, 201)

      assert %{
               "credential" => %{
                 "id" => ^id,
                 "name" => "Acme DHIS2",
                 "schema" => "raw",
                 "user_id" => user_id,
                 "projects" => [_, _]
               },
               "errors" => %{}
             } = response

      assert user_id == owner.id

      assert linked_project_ids(response) ==
               Enum.sort([project_a.id, project_b.id])

      refute conn.resp_body =~ @secret
      assert main_body(id) == %{"password" => @secret}
    end

    test "replaces name, schema and main body; keeps other bodies and every link",
         %{conn: conn} do
      owner = insert(:user)
      [earlier, requested] = insert_pair(:project)
      credential = existing_credential(owner, earlier)

      conn =
        put_credential(
          conn,
          credential.id,
          credential_body(%{
            "name" => "Renamed",
            "owner" => owner.email,
            "credential_bodies" => [
              %{"name" => "main", "body" => %{"password" => @secret}}
            ],
            "project_credentials" => links([requested.id])
          })
        )

      response = json_response(conn, 200)

      assert response["credential"]["name"] == "Renamed"

      assert linked_project_ids(response) ==
               Enum.sort([earlier.id, requested.id])

      [earlier_link] =
        Enum.filter(
          response["credential"]["project_credentials"],
          &(&1["project_id"] == earlier.id)
        )

      assert earlier_link["id"] ==
               Repo.get_by!(Lightning.Projects.ProjectCredential,
                 project_id: earlier.id,
                 credential_id: credential.id
               ).id

      refute conn.resp_body =~ @secret
      assert main_body(credential.id) == %{"password" => @secret}

      assert Credentials.get_credential_body(credential.id, "staging").body ==
               %{"password" => "staging"}
    end

    test "re-sending what is stored answers 200 and changes nothing", %{
      conn: conn
    } do
      owner = insert(:user)
      project = insert(:project)
      id = Ecto.UUID.generate()

      body =
        credential_body(%{
          "owner" => owner.email,
          "project_credentials" => links([project.id])
        })

      first = conn |> put_credential(id, body) |> json_response(201)
      second = conn |> put_credential(id, body) |> json_response(200)

      assert second["credential"]["project_credentials"] ==
               first["credential"]["project_credentials"]
    end

    test "will not rewrite another owner's credential through a new owner", %{
      conn: conn
    } do
      owner = insert(:user)
      credential = existing_credential(owner, insert(:project))
      other = insert(:user)

      conn =
        put_credential(
          conn,
          credential.id,
          credential_body(%{"name" => "Hijacked", "owner" => other.email})
        )

      assert json_response(conn, 409) == %{"error" => "id_taken"}

      assert %Credential{name: "Acme DHIS2", user_id: owner_id} =
               Repo.reload!(credential)

      assert owner_id == owner.id
      assert main_body(credential.id) == %{"password" => "old"}
    end

    test "answers name_taken when the owner holds the name under another id",
         %{conn: conn} do
      owner = insert(:user)
      held = insert(:credential, user: owner, name: "Taken")
      renamed = insert(:credential, user: owner, name: "Mine")
      new_id = Ecto.UUID.generate()

      created =
        put_credential(
          conn,
          new_id,
          credential_body(%{"name" => "Taken", "owner" => owner.email})
        )

      assert json_response(created, 409) == %{"error" => "name_taken"}
      refute Repo.get(Credential, new_id)

      replaced =
        put_credential(
          conn,
          renamed.id,
          credential_body(%{"name" => held.name, "owner" => owner.email})
        )

      assert json_response(replaced, 409) == %{"error" => "name_taken"}
      assert Repo.reload!(renamed).name == "Mine"
    end

    test "refuses a body it cannot take with 422, flat and under its key", %{
      conn: conn
    } do
      owner = insert(:user)
      project_id = insert(:project).id
      main = %{"name" => "main", "body" => %{"a" => "b"}}

      refused = [
        unknown_key: {%{"external_id" => "x"}, "external_id"},
        no_bodies: {%{"credential_bodies" => []}, "credential_bodies"},
        missing_bodies: {%{"credential_bodies" => nil}, "credential_bodies"},
        two_bodies:
          {%{"credential_bodies" => [main, %{main | "name" => "staging"}]},
           "credential_bodies"},
        not_main:
          {%{"credential_bodies" => [%{main | "name" => "staging"}]},
           "credential_bodies"},
        body_not_object:
          {%{"credential_bodies" => [%{main | "body" => "text"}]},
           "credential_bodies"},
        bodies_not_list: {%{"credential_bodies" => main}, "credential_bodies"},
        link_without_project:
          {%{"project_credentials" => [%{"id" => project_id}]},
           "project_credentials"},
        link_not_uuid:
          {%{"project_credentials" => [%{"project_id" => "acme"}]},
           "project_credentials"},
        links_not_list:
          {%{"project_credentials" => %{"project_id" => project_id}},
           "project_credentials"},
        unknown_owner: {%{"owner" => "nobody@example.com"}, "owner"},
        missing_owner: {%{"owner" => nil}, "owner"},
        other_id: {%{"id" => Ecto.UUID.generate()}, "id"},
        blank_name: {%{"name" => ""}, "name"}
      ]

      for {case_name, {overrides, key}} <- refused do
        id = Ecto.UUID.generate()

        body =
          %{"owner" => owner.email}
          |> credential_body()
          |> Map.merge(overrides)
          |> Map.reject(fn {_key, value} -> is_nil(value) end)

        response = conn |> put_credential(id, body) |> json_response(422)

        assert %{"errors" => %{^key => [_ | _] = messages} = errors} = response,
               "#{case_name}: #{inspect(response)}"

        assert map_size(errors) == 1 and Enum.all?(messages, &is_binary/1),
               "#{case_name}: #{inspect(response)}"

        refute Repo.get(Credential, id), "#{case_name} created a credential"
      end

      assert %{"errors" => %{"id" => [_]}} =
               conn
               |> put_credential(
                 "not-a-uuid",
                 credential_body(%{"owner" => owner.email})
               )
               |> json_response(422)
    end

    test "never quotes a submitted value in a 422", %{conn: conn} do
      owner = insert(:user)
      planted = "PLANTED-VALUE"

      bodies = [
        %{
          "owner" => owner.email,
          "name" => planted <> "\u0007",
          "schema" => String.duplicate(planted, 10)
        },
        %{"owner" => planted <> "@example.com"},
        %{
          "owner" => owner.email,
          "credential_bodies" => [%{"name" => planted, "body" => planted}],
          "project_credentials" => [%{"project_id" => planted}]
        }
      ]

      for overrides <- bodies do
        conn =
          put_credential(conn, Ecto.UUID.generate(), credential_body(overrides))

        assert %{"errors" => errors} = json_response(conn, 422)
        assert errors != %{}
        refute conn.resp_body =~ planted
      end
    end

    test "refuses a listed project that does not exist with 403", %{conn: conn} do
      owner = insert(:user)
      id = Ecto.UUID.generate()

      conn =
        put_credential(
          conn,
          id,
          credential_body(%{
            "owner" => owner.email,
            "project_credentials" => links([Ecto.UUID.generate()])
          })
        )

      assert json_response(conn, 403) == %{"error" => "Forbidden"}
      refute Repo.get(Credential, id)
    end
  end

  describe "for a service account without credentials:write" do
    test "PUT and GET are refused for insufficient scope", %{conn: conn} do
      {conn, _account} = with_service_account(conn, ["projects:write"])
      owner = insert(:user)
      credential = insert(:credential, user: owner)

      for refused <- [
            put_credential(
              conn,
              Ecto.UUID.generate(),
              credential_body(%{"owner" => owner.email})
            ),
            get(conn, ~p"/api/credentials/#{credential.id}")
          ] do
        assert json_response(refused, 403) == %{"error" => "insufficient_scope"}

        assert get_resp_header(refused, "www-authenticate") == [
                 ~s(Bearer error="insufficient_scope")
               ]
      end
    end
  end

  describe "PUT, for a person's token" do
    test "creates a credential they own without naming an owner", %{conn: conn} do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user, role: :editor}])
      id = Ecto.UUID.generate()

      response =
        conn
        |> with_pat(user)
        |> put_credential(
          id,
          credential_body(%{"project_credentials" => links([project.id])})
        )
        |> json_response(201)

      assert response["credential"]["user_id"] == user.id
      assert linked_project_ids(response) == [project.id]
    end

    test "may name themselves as owner, but no one else", %{conn: conn} do
      user = insert(:user)
      other = insert(:user)
      conn = with_pat(conn, user)

      assert conn
             |> put_credential(
               Ecto.UUID.generate(),
               credential_body(%{"owner" => String.upcase(user.email)})
             )
             |> json_response(201)

      id = Ecto.UUID.generate()

      assert conn
             |> put_credential(id, credential_body(%{"owner" => other.email}))
             |> json_response(403)

      refute Repo.get(Credential, id)
    end

    test "cannot rewrite a credential someone else owns", %{conn: conn} do
      credential = insert(:credential, user: insert(:user), name: "Theirs")

      conn =
        conn
        |> with_pat(insert(:user))
        |> put_credential(credential.id, credential_body(%{}))

      assert json_response(conn, 409) == %{"error" => "id_taken"}
      assert Repo.reload!(credential).name == "Theirs"
    end

    test "links only to projects where they may create a project credential",
         %{conn: conn} do
      user = insert(:user)
      viewing = insert(:project, project_users: [%{user: user, role: :viewer}])
      id = Ecto.UUID.generate()

      conn =
        conn
        |> with_pat(user)
        |> put_credential(
          id,
          credential_body(%{"project_credentials" => links([viewing.id])})
        )

      assert json_response(conn, 403) == %{"error" => "Forbidden"}
      refute Repo.get(Credential, id)
    end
  end

  describe "GET" do
    test "a service account with the scope reads any credential, never its body",
         %{conn: conn} do
      {conn, _account} = with_service_account(conn, ["credentials:write"])
      owner = insert(:user)
      project = insert(:project)
      credential = existing_credential(owner, project)

      conn = get(conn, ~p"/api/credentials/#{credential.id}")

      assert %{
               "credential" => %{
                 "id" => id,
                 "user_id" => user_id,
                 "projects" => [%{"id" => project_id}]
               },
               "errors" => %{}
             } = response = json_response(conn, 200)

      assert {id, user_id, project_id} == {credential.id, owner.id, project.id}
      assert linked_project_ids(response) == [project.id]
      refute conn.resp_body =~ "password"

      assert conn
             |> get(~p"/api/credentials/#{Ecto.UUID.generate()}")
             |> json_response(404)
    end

    test "a person reads only their own, seeing every link but only their projects",
         %{conn: conn} do
      owner = insert(:user)
      theirs = insert(:project, project_users: [%{user: owner, role: :owner}])
      elsewhere = insert(:project)
      credential = existing_credential(owner, theirs)
      insert(:project_credential, credential: credential, project: elsewhere)

      response =
        conn
        |> with_pat(owner)
        |> get(~p"/api/credentials/#{credential.id}")
        |> json_response(200)

      assert linked_project_ids(response) == Enum.sort([theirs.id, elsewhere.id])
      assert [%{"id" => theirs_id}] = response["credential"]["projects"]
      assert theirs_id == theirs.id

      assert conn
             |> with_pat(insert(:user))
             |> get(~p"/api/credentials/#{credential.id}")
             |> json_response(403)
    end
  end

  describe "for a repo connection" do
    test "PUT and GET are refused with 403", %{conn: conn} do
      project = insert(:project)
      repo_connection = insert(:project_repo_connection, project: project)
      credential = insert(:credential, user: insert(:user))

      conn =
        put_req_header(
          conn,
          "authorization",
          "Bearer " <> repo_connection.access_token
        )

      for refused <- [
            put_credential(conn, Ecto.UUID.generate(), credential_body(%{})),
            get(conn, ~p"/api/credentials/#{credential.id}")
          ] do
        assert json_response(refused, 403) == %{"error" => "Forbidden"}
      end
    end
  end
end
