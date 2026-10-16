defmodule LightningWeb.API.CredentialControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers

  # Sample curl requests:
  #
  #   # List your credentials
  #   curl http://localhost:4000/api/credentials \
  #     -H "Authorization: Bearer $TOKEN" -H "Accept: application/json"
  #
  #   # List credentials for a project
  #   curl http://localhost:4000/api/projects/$PROJECT_ID/credentials \
  #     -H "Authorization: Bearer $TOKEN" -H "Accept: application/json"
  #
  #   # Create a credential
  #   curl -X POST http://localhost:4000/api/credentials \
  #     -H "Authorization: Bearer $TOKEN" -H "Content-Type: application/json" \
  #     -d '{"name":"My Cred","schema":"raw","credential_bodies":[{"name":"main","body":{"key":"val"}}]}'
  #
  #   # Delete a credential
  #   curl -X DELETE http://localhost:4000/api/credentials/$CREDENTIAL_ID \
  #     -H "Authorization: Bearer $TOKEN"

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "without a token" do
    test "index gets a 401", %{conn: conn} do
      conn = get(conn, ~p"/api/credentials")
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end

    test "project credentials index gets a 401", %{conn: conn} do
      conn = get(conn, ~p"/api/projects/#{Ecto.UUID.generate()}/credentials")
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end

    test "create gets a 401", %{conn: conn} do
      conn = post(conn, ~p"/api/credentials", %{})
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end

    test "delete gets a 401", %{conn: conn} do
      conn = delete(conn, ~p"/api/credentials/#{Ecto.UUID.generate()}")
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "with invalid token" do
    test "index gets a 401", %{conn: conn} do
      token = "InvalidToken"
      conn = conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      conn = get(conn, ~p"/api/credentials")
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end

    test "project credentials index gets a 401", %{conn: conn} do
      token = "InvalidToken"
      conn = conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      conn = get(conn, ~p"/api/projects/#{Ecto.UUID.generate()}/credentials")
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end

    test "create gets a 401", %{conn: conn} do
      token = "InvalidToken"
      conn = conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      conn = post(conn, ~p"/api/credentials", %{})
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end

    test "delete gets a 401", %{conn: conn} do
      token = "InvalidToken"
      conn = conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      conn = delete(conn, ~p"/api/credentials/#{Ecto.UUID.generate()}")
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "index" do
    setup [:assign_bearer_for_api]

    test "lists all credentials owned by the user", %{conn: conn, user: user} do
      # Create some credentials for the user
      _credential1 =
        insert(:credential, user: user, name: "First Credential", schema: "raw")

      _credential2 =
        insert(:credential, user: user, name: "Second Credential", schema: "raw")

      # Create a credential for another user (should not appear)
      other_user = insert(:user)

      _other_credential =
        insert(:credential,
          user: other_user,
          name: "Other User Credential",
          schema: "raw"
        )

      conn = get(conn, ~p"/api/credentials")
      response = json_response(conn, 200)

      assert %{
               "credentials" => credentials,
               "errors" => %{}
             } = response

      assert length(credentials) == 2

      # Check that credentials are returned without body field
      returned_names = Enum.map(credentials, & &1["name"]) |> Enum.sort()
      assert returned_names == ["First Credential", "Second Credential"]

      # Verify body field is excluded for security
      Enum.each(credentials, fn credential ->
        refute Map.has_key?(credential, "body")
        assert credential["user_id"] == user.id
      end)

      # Check specific credential structure
      first_credential =
        Enum.find(credentials, &(&1["name"] == "First Credential"))

      assert %{
               "id" => _,
               "name" => "First Credential",
               "schema" => _,
               "external_id" => _,
               "user_id" => user_id,
               "project_credentials" => _,
               "projects" => _,
               "inserted_at" => _,
               "updated_at" => _
             } = first_credential

      assert user_id == user.id
      # production field no longer exists
      refute Map.has_key?(first_credential, "production")
    end

    test "names a linked project only to a caller who may access it", %{
      conn: conn,
      user: user
    } do
      # A member who has not enrolled in MFA may not access this project, so the
      # response does not name it, just as showing one credential doesn't.
      mfa_project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user_id: user.id, role: :owner}]
        )

      open_project =
        insert(:project, project_users: [%{user_id: user.id, role: :owner}])

      insert(:credential,
        user: user,
        schema: "raw",
        project_credentials: [
          %{project_id: mfa_project.id},
          %{project_id: open_project.id}
        ]
      )

      assert %{"credentials" => [credential]} =
               conn |> get(~p"/api/credentials") |> json_response(200)

      assert Enum.map(credential["projects"], & &1["id"]) == [open_project.id]

      assert Enum.map(credential["project_credentials"], & &1["project_id"]) ==
               [open_project.id]
    end

    test "returns empty list when user has no credentials", %{
      conn: conn,
      user: _user
    } do
      conn = get(conn, ~p"/api/credentials")
      response = json_response(conn, 200)

      assert %{
               "credentials" => [],
               "errors" => %{}
             } = response
    end

    test "includes project associations in the response", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project, project_users: [%{user_id: user.id, role: :owner}])

      _credential =
        insert(:credential,
          user: user,
          name: "Project Credential",
          schema: "raw",
          project_credentials: [%{project_id: project.id}]
        )

      conn = get(conn, ~p"/api/credentials")
      response = json_response(conn, 200)

      assert %{"credentials" => [credential_data]} = response
      assert credential_data["name"] == "Project Credential"
      assert length(credential_data["project_credentials"]) == 1
      assert length(credential_data["projects"]) == 1

      project_data = List.first(credential_data["projects"])
      assert project_data["id"] == project.id
      assert project_data["name"] == project.name
    end
  end

  describe "index for specific project" do
    setup [:assign_bearer_for_api]

    test "lists all credentials in a project when user has access", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project, project_users: [%{user_id: user.id, role: :editor}])

      # Create credentials for different users but in the same project
      _user_credential =
        insert(:credential,
          user: user,
          name: "User Credential",
          schema: "raw",
          project_credentials: [%{project_id: project.id}]
        )

      other_user = insert(:user)

      _other_user_credential =
        insert(:credential,
          user: other_user,
          name: "Other User Credential",
          schema: "raw",
          project_credentials: [%{project_id: project.id}]
        )

      # Create a credential not in this project (should not appear)
      _unrelated_credential =
        insert(:credential,
          user: user,
          name: "Unrelated Credential",
          schema: "raw"
        )

      conn = get(conn, ~p"/api/projects/#{project.id}/credentials")
      response = json_response(conn, 200)

      assert %{
               "credentials" => credentials,
               "errors" => %{}
             } = response

      assert length(credentials) == 2

      # Should include credentials from all users that have access to this project
      returned_names = Enum.map(credentials, & &1["name"]) |> Enum.sort()
      assert returned_names == ["Other User Credential", "User Credential"]

      # Verify body field is excluded for security
      Enum.each(credentials, fn credential ->
        refute Map.has_key?(credential, "body")
      end)
    end

    test "does not disclose sibling projects the caller is not a member of", %{
      conn: conn,
      user: user
    } do
      project_a =
        insert(:project,
          name: "project-a",
          project_users: [%{user_id: user.id, role: :viewer}]
        )

      # A different tenant's project the caller has no membership in.
      other_project = insert(:project, name: "other-tenant-secret")

      owner = insert(:user)

      _shared_credential =
        insert(:credential,
          user: owner,
          name: "Shared Credential",
          schema: "raw",
          project_credentials: [
            %{project_id: project_a.id},
            %{project_id: other_project.id}
          ]
        )

      conn = get(conn, ~p"/api/projects/#{project_a.id}/credentials")

      assert %{"credentials" => [credential]} = json_response(conn, 200)

      rendered_project_ids = Enum.map(credential["projects"], & &1["id"])
      assert project_a.id in rendered_project_ids
      refute other_project.id in rendered_project_ids

      refute Enum.any?(
               credential["projects"],
               &(&1["name"] == "other-tenant-secret")
             )

      # The sibling project's UUID must not leak via project_credentials either.
      pc_project_ids =
        Enum.map(credential["project_credentials"], & &1["project_id"])

      assert project_a.id in pc_project_ids
      refute other_project.id in pc_project_ids
    end

    test "shows the caller's own association when the project is a sandbox", %{
      conn: conn,
      user: user
    } do
      root = insert(:project)

      sandbox =
        insert(:project,
          parent: root,
          project_users: [%{user_id: user.id, role: :viewer}]
        )

      owner = insert(:user)

      _credential =
        insert(:credential,
          user: owner,
          name: "Sandbox Credential",
          schema: "raw",
          project_credentials: [%{project_id: sandbox.id}]
        )

      conn = get(conn, ~p"/api/projects/#{sandbox.id}/credentials")

      assert %{"credentials" => [credential]} = json_response(conn, 200)
      assert Enum.map(credential["projects"], & &1["id"]) == [sandbox.id]

      assert Enum.map(credential["project_credentials"], & &1["project_id"]) ==
               [sandbox.id]
    end

    test "returns 404 when user is not a member of the project", %{
      conn: conn,
      user: _user
    } do
      other_user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: other_user.id, role: :owner}]
        )

      conn = get(conn, ~p"/api/projects/#{project.id}/credentials")
      assert_problem(conn, 404, :not_found, [])
    end

    test "tells a member, and only a member, that the project is scheduled for deletion",
         %{conn: conn, user: user} do
      scheduled_deletion = DateTime.utc_now() |> DateTime.truncate(:second)

      member_of =
        insert(:project,
          project_users: [%{user_id: user.id, role: :editor}],
          scheduled_deletion: scheduled_deletion
        )

      stranger_to = insert(:project, scheduled_deletion: scheduled_deletion)

      conn
      |> get(~p"/api/projects/#{member_of.id}/credentials")
      |> assert_problem(409, :scheduled_for_deletion, [])

      conn
      |> get(~p"/api/projects/#{stranger_to.id}/credentials")
      |> assert_problem(404, :not_found, [])
    end

    test "returns 404 when project does not exist", %{conn: conn, user: _user} do
      non_existent_id = Ecto.UUID.generate()

      conn = get(conn, ~p"/api/projects/#{non_existent_id}/credentials")
      assert_problem(conn, 404, :not_found, [])
    end

    test "returns empty list when project has no credentials", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project, project_users: [%{user_id: user.id, role: :owner}])

      conn = get(conn, ~p"/api/projects/#{project.id}/credentials")
      response = json_response(conn, 200)

      assert %{
               "credentials" => [],
               "errors" => %{}
             } = response
    end

    test "allows access for support users with project access", %{conn: conn} do
      support_user = insert(:user, support_user: true)
      project = insert(:project, allow_support_access: true)

      _credential =
        insert(:credential,
          user: support_user,
          name: "Support Credential",
          schema: "raw",
          project_credentials: [%{project_id: project.id}]
        )

      token = Lightning.Accounts.generate_api_token(support_user)
      conn = conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")

      conn = get(conn, ~p"/api/projects/#{project.id}/credentials")
      response = json_response(conn, 200)

      assert %{"credentials" => [credential_data]} = response
      assert credential_data["name"] == "Support Credential"
    end

    test "includes project information in credential data", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project, project_users: [%{user_id: user.id, role: :admin}])

      _credential =
        insert(:credential,
          user: user,
          name: "Project Credential",
          schema: "raw",
          project_credentials: [%{project_id: project.id}]
        )

      conn = get(conn, ~p"/api/projects/#{project.id}/credentials")
      response = json_response(conn, 200)

      assert %{"credentials" => [credential_data]} = response
      assert length(credential_data["projects"]) == 1
      assert length(credential_data["project_credentials"]) == 1

      project_data = List.first(credential_data["projects"])
      assert project_data["id"] == project.id
      assert project_data["name"] == project.name
    end
  end

  describe "create" do
    setup [:assign_bearer_for_api]

    test "refuses a repo connection token instead of crashing", %{conn: conn} do
      # `require_authenticated_api_resource` lets these through the pipeline,
      # and a credential belongs to a person, so there is no sensible owner to
      # give it. It used to fall over on the user association and come back a
      # 422; it must not become a 500 now that the actor is threaded through.
      repo_connection =
        insert(:project_repo_connection, project: insert(:project))

      conn =
        Plug.Conn.put_req_header(
          conn,
          "authorization",
          "Bearer #{repo_connection.access_token}"
        )

      conn
      |> post(~p"/api/credentials", %{
        "name" => "Planted",
        "schema" => "raw",
        "credential_bodies" => [
          %{"name" => "main", "body" => %{"a" => "b"}}
        ]
      })
      |> assert_problem(403, :insufficient_scope, [])

      refute Lightning.Repo.get_by(Lightning.Credentials.Credential,
               name: "Planted"
             )

      # Listing crashed the same way, for the same reason, on both routes.
      conn
      |> get(~p"/api/credentials")
      |> assert_problem(403, :insufficient_scope, [])

      project = insert(:project)

      conn
      |> get(~p"/api/projects/#{project.id}/credentials")
      |> assert_problem(403, :insufficient_scope, [])
    end

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
      # body should be excluded
      refute Map.has_key?(response["credential"], "body")
      # production field no longer exists
      refute Map.has_key?(response["credential"], "production")
    end

    test "creates a credential with project associations when user has access",
         %{conn: conn, user: user} do
      project =
        insert(:project, project_users: [%{user_id: user.id, role: :editor}])

      credential_attrs = %{
        "name" => "Project Credential",
        "schema" => "raw",
        "credential_bodies" => [
          %{
            "name" => "main",
            "body" => %{"api_key" => "secret"}
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
                 "id" => id,
                 "name" => "Project Credential",
                 "user_id" => user_id,
                 "project_credentials" => [project_credential],
                 "projects" => [project_data]
               }
             } = response

      assert is_binary(id)
      assert user_id == user.id
      assert project_credential["project_id"] == project.id
      assert project_data["id"] == project.id
      assert project_data["name"] == project.name
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

    test "answers 400 malformed for a body that is not a JSON object", %{
      conn: conn,
      user: user
    } do
      for body <- [[%{"name" => "Listed", "schema" => "raw"}], "Listed", 7] do
        conn
        |> put_req_header("content-type", "application/json")
        |> post(~p"/api/credentials", Jason.encode!(body))
        |> assert_problem(400, :malformed, [])
      end

      assert Lightning.Credentials.list_credentials(user) == []
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

    test "refuses a link to a project the user can't see as naming nothing",
         %{conn: conn, user: user} do
      other_user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: other_user.id, role: :owner}]
        )

      credential_attrs = %{
        "name" => "Unauthorized Credential",
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

      conn
      |> post(~p"/api/credentials", credential_attrs)
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/project_credentials/0/project_id",
          "code" => "not_found",
          "detail" => "names nothing you can see"
        }
      ])

      assert Lightning.Credentials.list_credentials(user) == []
    end

    test "refuses a link to a project where the user is a viewer", %{
      conn: conn,
      user: user
    } do
      project =
        insert(:project, project_users: [%{user_id: user.id, role: :viewer}])

      credential_attrs = %{
        "name" => "Viewer Credential",
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

      conn
      |> post(~p"/api/credentials", credential_attrs)
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/project_credentials/0/project_id",
          "code" => "no_access",
          "detail" => "you may not link a credential to this project"
        }
      ])
    end

    test "refuses a link to a project that does not exist as naming nothing", %{
      conn: conn,
      user: _user
    } do
      credential_attrs = %{
        "name" => "Nonexistent Project Credential",
        "schema" => "raw",
        "credential_bodies" => [
          %{
            "name" => "main",
            "body" => %{"secret" => "value"}
          }
        ],
        "project_credentials" => [
          %{"project_id" => Ecto.UUID.generate()}
        ]
      }

      conn
      |> post(~p"/api/credentials", credential_attrs)
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/project_credentials/0/project_id",
          "code" => "not_found",
          "detail" => "names nothing you can see"
        }
      ])
    end

    test "refuses a malformed link with 422 at the link", %{
      conn: conn,
      user: user
    } do
      for {links, pointer, code, detail} <- [
            {[%{"project_id" => "not-a-uuid"}],
             "#/project_credentials/0/project_id", "not_found",
             "names nothing you can see"},
            {[%{"project_id" => 42}], "#/project_credentials/0/project_id",
             "type", "is invalid"},
            {[%{}], "#/project_credentials/0/project_id", "required",
             "can't be blank"},
            {["acme"], "#/project_credentials/0", "type", "is invalid"},
            {%{"project_id" => Ecto.UUID.generate()}, "#/project_credentials",
             "type", "is invalid"}
          ] do
        conn
        |> post(~p"/api/credentials", %{
          "name" => "Malformed Link",
          "schema" => "raw",
          "credential_bodies" => [%{"name" => "main", "body" => %{}}],
          "project_credentials" => links
        })
        |> assert_problem(422, :invalid, [
          %{"pointer" => pointer, "code" => code, "detail" => detail}
        ])
      end

      assert Lightning.Credentials.list_credentials(user) == []
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

    test "fails with invalid credential data", %{conn: conn, user: _user} do
      credential_attrs = %{
        # Invalid: empty name
        "name" => "",
        "schema" => "raw",
        "credential_bodies" => [
          %{
            "name" => "main",
            "body" => %{"secret" => "value"}
          }
        ]
      }

      conn
      |> post(~p"/api/credentials", credential_attrs)
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/name",
          "code" => "required",
          "detail" => "can't be blank"
        }
      ])
    end

    test "fails when missing required fields", %{conn: conn, user: _user} do
      credential_attrs = %{
        "name" => ""
      }

      conn
      |> post(~p"/api/credentials", credential_attrs)
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/name",
          "code" => "required",
          "detail" => "can't be blank"
        },
        %{
          "pointer" => "#/schema",
          "code" => "required",
          "detail" => "can't be blank"
        }
      ])
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

    test "returns 201 created status", %{conn: conn, user: _user} do
      credential_attrs = %{
        "name" => "Status Test",
        "schema" => "raw",
        "credential_bodies" => [
          %{
            "name" => "main",
            "body" => %{"secret" => "value"}
          }
        ]
      }

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      assert json_response(conn, 201)
    end

    test "refuses only the link it can't make, at its position in the request",
         %{conn: conn, user: user} do
      accessible_project =
        insert(:project, project_users: [%{user_id: user.id, role: :editor}])

      # No user access
      inaccessible_project = insert(:project)

      credential_attrs = %{
        "name" => "Mixed Access Credential",
        "schema" => "raw",
        "credential_bodies" => [
          %{
            "name" => "main",
            "body" => %{"secret" => "value"}
          }
        ],
        "project_credentials" => [
          %{"project_id" => inaccessible_project.id},
          %{"project_id" => accessible_project.id},
          %{"project_id" => inaccessible_project.id}
        ]
      }

      conn
      |> post(~p"/api/credentials", credential_attrs)
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/project_credentials/0/project_id",
          "code" => "not_found",
          "detail" => "names nothing you can see"
        },
        %{
          "pointer" => "#/project_credentials/2/project_id",
          "code" => "not_found",
          "detail" => "names nothing you can see"
        }
      ])

      assert Lightning.Credentials.list_credentials(user) == []
    end
  end

  describe "editor role permissions" do
    setup [:assign_bearer_for_api]

    test "editor can create project credentials", %{conn: conn, user: user} do
      project =
        insert(:project, project_users: [%{user_id: user.id, role: :editor}])

      credential_attrs = %{
        "name" => "Editor Credential",
        "schema" => "raw",
        "credential_bodies" => [
          %{
            "name" => "main",
            "body" => %{"secret" => "value"}
          }
        ],
        "project_credentials" => [%{"project_id" => project.id}]
      }

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      assert json_response(conn, 201)
    end
  end

  describe "admin role permissions" do
    setup [:assign_bearer_for_api]

    test "admin can create project credentials", %{conn: conn, user: user} do
      project =
        insert(:project, project_users: [%{user_id: user.id, role: :admin}])

      credential_attrs = %{
        "name" => "Admin Credential",
        "schema" => "raw",
        "credential_bodies" => [
          %{
            "name" => "main",
            "body" => %{"secret" => "value"}
          }
        ],
        "project_credentials" => [%{"project_id" => project.id}]
      }

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      assert json_response(conn, 201)
    end
  end

  describe "owner role permissions" do
    setup [:assign_bearer_for_api]

    test "owner can create project credentials", %{conn: conn, user: user} do
      project =
        insert(:project, project_users: [%{user_id: user.id, role: :owner}])

      credential_attrs = %{
        "name" => "Owner Credential",
        "schema" => "raw",
        "credential_bodies" => [
          %{
            "name" => "main",
            "body" => %{"secret" => "value"}
          }
        ],
        "project_credentials" => [%{"project_id" => project.id}]
      }

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      assert json_response(conn, 201)
    end
  end

  describe "create, refused by what it writes" do
    setup [:assign_bearer_for_api]

    defp oauth_token(overrides) do
      Map.merge(
        %{
          "access_token" => "access",
          "refresh_token" => "refresh",
          "token_type" => "Bearer",
          "scope" => "read write",
          "expires_in" => 3600
        },
        overrides
      )
    end

    test "refuses an OAuth token at the key it refuses, in the body at its position",
         %{conn: conn, user: user} do
      conn
      |> post(~p"/api/credentials", %{
        "name" => "OAuth",
        "schema" => "oauth",
        "credential_bodies" => [
          %{"name" => "main", "body" => oauth_token(%{})},
          %{
            "name" => "staging",
            "body" => oauth_token(%{"token_type" => "Basic"})
          }
        ]
      })
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/credential_bodies/1/body/token_type",
          "code" => "not_allowed",
          "detail" => "Unsupported token type. Expected 'Bearer'"
        }
      ])

      conn
      |> post(~p"/api/credentials", %{
        "name" => "OAuth",
        "schema" => "oauth",
        "credential_bodies" => [
          %{
            "name" => "main",
            "body" => Map.delete(oauth_token(%{}), "access_token")
          }
        ]
      })
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/credential_bodies/0/body/access_token",
          "code" => "required",
          "detail" => "Missing required OAuth field: access_token"
        }
      ])

      assert Lightning.Credentials.list_credentials(user) == []
    end

    test "answers 409 taken for a name the user already holds", %{
      conn: conn,
      user: user
    } do
      insert(:credential, user: user, name: "Taken")

      conn
      |> post(~p"/api/credentials", %{
        "name" => "Taken",
        "schema" => "raw",
        "credential_bodies" => [%{"name" => "main", "body" => %{"a" => "b"}}]
      })
      |> assert_problem(409, :taken, [
        %{
          "pointer" => "#/name",
          "code" => "taken",
          "detail" => "you have another credential with the same name"
        }
      ])
    end
  end

  describe "delete" do
    setup [:assign_bearer_for_api]

    test "deletes a credential owned by the user", %{conn: conn, user: user} do
      credential =
        insert(:credential, user: user, name: "To Be Deleted", schema: "raw")

      conn = delete(conn, ~p"/api/credentials/#{credential.id}")
      assert response(conn, 204) == ""

      # Verify credential is deleted
      refute Lightning.Credentials.get_credential(credential.id)
    end

    test "returns 404 when credential does not exist", %{conn: conn, user: _user} do
      non_existent_id = Ecto.UUID.generate()

      conn = delete(conn, ~p"/api/credentials/#{non_existent_id}")
      assert_problem(conn, 404, :not_found, [])
    end

    test "answers 404 for another user's credential the caller can't see", %{
      conn: conn
    } do
      other_credential =
        insert(:credential, user: insert(:user), schema: "raw")

      conn
      |> delete(~p"/api/credentials/#{other_credential.id}")
      |> assert_problem(404, :not_found, [])

      assert Lightning.Credentials.get_credential(other_credential.id)
    end

    test "answers 403 for another user's credential the caller sees through a project",
         %{conn: conn, user: user} do
      project =
        insert(:project, project_users: [%{user_id: user.id, role: :owner}])

      other_credential =
        insert(:credential,
          user: insert(:user),
          schema: "raw",
          project_credentials: [%{project_id: project.id}]
        )

      conn
      |> delete(~p"/api/credentials/#{other_credential.id}")
      |> assert_problem(403, :forbidden, [])

      assert Lightning.Credentials.get_credential(other_credential.id)
    end

    test "answers 409 in_use for a credential runs have used", %{
      conn: conn,
      user: user
    } do
      credential = insert(:credential, user: user, schema: "raw")
      insert(:step, credential: credential)

      conn
      |> delete(~p"/api/credentials/#{credential.id}")
      |> assert_problem(409, :in_use, [])

      assert Lightning.Credentials.get_credential(credential.id)
    end

    test "deletes credential with project associations", %{
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

    test "handles invalid UUID format", %{conn: conn, user: _user} do
      conn = delete(conn, ~p"/api/credentials/invalid-uuid")
      assert_problem(conn, 404, :not_found, [])
    end
  end

  describe "error answers on every credentials route" do
    setup [:assign_bearer_for_api]

    test "never quote a value from the request", %{conn: conn, user: user} do
      planted =
        plant_sentinel(%{
          "id" => nil,
          "name" => nil,
          "schema" => nil,
          "colour" => nil,
          "credential_bodies" => [%{"name" => nil, "body" => %{"key" => nil}}],
          "project_credentials" => [%{"project_id" => nil, "extra" => nil}]
        })

      conn
      |> get(~p"/api/projects/#{planted["name"]}/credentials")
      |> refute_sentinel()
      |> assert_problem(404, :not_found, [])

      conn
      |> get(~p"/api/credentials?project_id=#{planted["name"]}")
      |> refute_sentinel()
      |> assert_problem(404, :not_found, [])

      conn
      |> post(~p"/api/credentials", planted)
      |> refute_sentinel()
      |> assert_problem(422, :invalid)

      conn
      |> post(~p"/api/credentials", %{
        "name" => "OAuth",
        "schema" => "oauth",
        "credential_bodies" =>
          plant_sentinel([
            %{
              "name" => "main",
              "body" => %{
                "access_token" => [nil],
                "refresh_token" => nil,
                "token_type" => nil,
                "scope" => nil,
                "expires_in" => nil
              }
            }
          ])
      })
      |> refute_sentinel()
      |> assert_problem(422, :invalid)

      conn
      |> get(~p"/api/credentials/#{planted["name"]}")
      |> refute_sentinel()
      |> assert_problem(404, :not_found, [])

      for path_id <- [planted["name"], Ecto.UUID.generate()] do
        conn
        |> put_req_header("content-type", "application/json")
        |> put(~p"/api/credentials/#{path_id}", Jason.encode!(planted))
        |> refute_sentinel()
      end

      conn
      |> put_req_header("content-type", "application/json")
      |> put(
        ~p"/api/credentials/#{Ecto.UUID.generate()}",
        Jason.encode!(Map.put(planted, "owner", user.email))
      )
      |> refute_sentinel()
      |> assert_problem(422, :invalid)

      conn
      |> delete(~p"/api/credentials/#{planted["name"]}")
      |> refute_sentinel()
      |> assert_problem(404, :not_found, [])
    end
  end
end
