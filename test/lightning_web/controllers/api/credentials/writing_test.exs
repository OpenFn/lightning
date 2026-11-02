defmodule LightningWeb.API.Credentials.WritingTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.ApiCredentialsHelpers
  import Lightning.ServiceAccountHelpers

  alias Lightning.Credentials
  alias Lightning.Credentials.Credential
  alias Lightning.Repo

  @secret LightningWeb.ApiCredentialsHelpers.secret()

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "creating with POST" do
    setup [:assign_bearer_for_api]

    test "creates a basic credential without project associations", %{
      conn: conn,
      user: user
    } do
      credential_attrs = %{
        "name" => "Test Credential",
        "schema" => "raw",
        "credential_bodies" => [
          %{
            "name" => "main",
            "body" => %{"username" => "test", "password" => "secret"}
          }
        ]
      }

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      response = json_response(conn, 201)

      assert %{
               "credential" => %{
                 "id" => id,
                 "name" => "Test Credential",
                 "schema" => "raw",
                 "external_id" => nil,
                 "user_id" => user_id,
                 "project_credentials" => [],
                 "projects" => []
               },
               "errors" => %{}
             } = response

      assert is_binary(id)
      assert user_id == user.id
      refute Map.has_key?(response["credential"], "body")
      refute Map.has_key?(response["credential"], "production")
    end

    test "creates a credential with multiple project associations", %{
      conn: conn,
      user: user
    } do
      project1 =
        insert(:project, project_users: [%{user_id: user.id, role: :admin}])

      project2 =
        insert(:project, project_users: [%{user_id: user.id, role: :owner}])

      credential_attrs = %{
        "name" => "Multi-Project Credential",
        "schema" => "raw",
        "credential_bodies" => [
          %{
            "name" => "main",
            "body" => %{"token" => "abc123"}
          }
        ],
        "project_credentials" => [
          %{"project_id" => project1.id},
          %{"project_id" => project2.id}
        ]
      }

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      response = json_response(conn, 201)

      assert %{
               "credential" => %{
                 "project_credentials" => project_credentials,
                 "projects" => projects
               }
             } = response

      assert length(project_credentials) == 2
      assert length(projects) == 2

      project_ids = Enum.map(projects, & &1["id"])
      assert project1.id in project_ids
      assert project2.id in project_ids
    end

    test "links a project named twice once", %{conn: conn, user: user} do
      project =
        insert(:project, project_users: [%{user_id: user.id, role: :editor}])

      credential_attrs = %{
        "name" => "Twice Linked",
        "schema" => "raw",
        "credential_bodies" => [%{"name" => "main", "body" => %{"a" => "b"}}],
        "project_credentials" => [
          %{"project_id" => project.id},
          %{"project_id" => project.id}
        ]
      }

      assert %{"credential" => %{"project_credentials" => [link]}} =
               conn
               |> post(~p"/api/credentials", credential_attrs)
               |> json_response(201)

      assert link["project_id"] == project.id
    end

    test "creates a credential with multiple environment bodies", %{
      conn: conn,
      user: user
    } do
      credential_attrs = %{
        "name" => "Multi-Environment Credential",
        "schema" => "raw",
        "credential_bodies" => [
          %{
            "name" => "main",
            "body" => %{"api_key" => "main_key"}
          },
          %{
            "name" => "production",
            "body" => %{"api_key" => "prod_key"}
          },
          %{
            "name" => "staging",
            "body" => %{"api_key" => "staging_key"}
          }
        ]
      }

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      response = json_response(conn, 201)

      assert %{
               "credential" => %{
                 "id" => id,
                 "name" => "Multi-Environment Credential",
                 "user_id" => user_id
               }
             } = response

      assert is_binary(id)
      assert user_id == user.id

      # Verify bodies were created
      credential = Lightning.Credentials.get_credential(id)
      credential = Lightning.Repo.preload(credential, :credential_bodies)
      assert length(credential.credential_bodies) == 3

      env_names =
        Enum.map(credential.credential_bodies, & &1.name) |> Enum.sort()

      assert env_names == ["main", "production", "staging"]
    end

    test "allows access when user is support user with project access", %{
      conn: conn
    } do
      support_user = insert(:user, support_user: true)
      project = insert(:project, allow_support_access: true)

      token = Lightning.Accounts.generate_api_token(support_user)
      conn = conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")

      credential_attrs = %{
        "name" => "Support User Credential",
        "schema" => "raw",
        "credential_bodies" => [
          %{
            "name" => "main",
            "body" => %{"secret" => "value"}
          }
        ],
        "project_credentials" => [
          %{"project_id" => project.id}
        ]
      }

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      response = json_response(conn, 201)

      assert %{
               "credential" => %{
                 "name" => "Support User Credential",
                 "user_id" => user_id
               }
             } = response

      assert user_id == support_user.id
    end

    test "cannot override user_id in request", %{conn: conn, user: user} do
      other_user = insert(:user)

      credential_attrs = %{
        "name" => "Test Credential",
        "schema" => "raw",
        "credential_bodies" => [
          %{
            "name" => "main",
            "body" => %{"secret" => "value"}
          }
        ],
        # This should be ignored
        "user_id" => other_user.id
      }

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      response = json_response(conn, 201)

      # Should use the authenticated user, not the provided user_id
      assert response["credential"]["user_id"] == user.id
      refute response["credential"]["user_id"] == other_user.id
    end

    test "links the project, whatever the caller's role in it", %{
      conn: conn,
      user: user
    } do
      for role <- [:editor, :admin, :owner] do
        project =
          insert(:project, project_users: [%{user_id: user.id, role: role}])

        assert %{
                 "credential" => %{
                   "user_id" => user_id,
                   "projects" => [%{"id" => project_id, "name" => project_name}],
                   "project_credentials" => [%{"project_id" => linked_id}]
                 }
               } =
                 conn
                 |> post(
                   ~p"/api/credentials",
                   credential_body(%{
                     "name" => "#{role} Credential",
                     "project_credentials" => links([project.id])
                   })
                 )
                 |> json_response(201)

        assert {user_id, project_id, project_name, linked_id} ==
                 {user.id, project.id, project.name, project.id}
      end
    end
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

      [project_a, project_b] =
        insert_pair(:project, project_users: [%{user: owner}])

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

      # Without projects:write the account sees the links, but no project
      # names.
      assert %{
               "credential" => %{
                 "id" => ^id,
                 "name" => "Acme DHIS2",
                 "schema" => "raw",
                 "user_id" => user_id,
                 "projects" => []
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
      earlier = insert(:project)
      requested = insert(:project, project_users: [%{user: owner}])
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
      project = insert(:project, project_users: [%{user: owner}])
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

    test "links a support user's credential to a project allowing support access",
         %{conn: conn} do
      owner = insert(:user, support_user: true)
      project = insert(:project, allow_support_access: true)
      id = Ecto.UUID.generate()

      conn =
        put_credential(
          conn,
          id,
          credential_body(%{
            "owner" => owner.email,
            "project_credentials" => links([project.id])
          })
        )

      assert linked_project_ids(json_response(conn, 201)) == [project.id]
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

      conn
      |> put_credential(id, credential_body(%{"owner" => other.email}))
      |> assert_problem(403, :forbidden, [])

      conn
      |> put_credential(
        id,
        credential_body(%{"owner" => "nobody@example.com"})
      )
      |> assert_problem(403, :forbidden, [])

      refute Repo.get(Credential, id)
    end

    test "keeps a link they can't see, and leaves it out of the response",
         %{conn: conn} do
      owner = insert(:user)
      theirs = insert(:project, project_users: [%{user: owner, role: :owner}])
      unseen = insert(:project)
      credential = existing_credential(owner, unseen)

      response =
        conn
        |> with_pat(owner)
        |> put_credential(
          credential.id,
          credential_body(%{"project_credentials" => links([theirs.id])})
        )
        |> json_response(200)

      assert linked_project_ids(response) == [theirs.id]
      refute inspect(response) =~ unseen.id

      assert Repo.get_by(Lightning.Projects.ProjectCredential,
               project_id: unseen.id,
               credential_id: credential.id
             )
    end
  end

  describe "deleting what the caller owns" do
    setup [:assign_bearer_for_api]

    test "deletes a credential the caller owns, with its project links", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project, project_users: [%{user_id: user.id, role: :owner}])

      credential =
        insert(:credential,
          user: user,
          name: "Credential with Projects",
          schema: "raw",
          project_credentials: [%{project_id: project.id}]
        )

      conn = delete(conn, ~p"/api/credentials/#{credential.id}")
      assert response(conn, 204) == ""

      # Verify credential and associations are deleted
      refute Lightning.Credentials.get_credential(credential.id)
    end
  end
end
