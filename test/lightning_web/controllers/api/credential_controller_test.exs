defmodule LightningWeb.API.CredentialControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

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

    test "returns 403 when user lacks access to project", %{
      conn: conn,
      user: _user
    } do
      other_user = insert(:user)

      project =
        insert(:project,
          project_users: [%{user_id: other_user.id, role: :owner}]
        )

      conn = get(conn, ~p"/api/projects/#{project.id}/credentials")
      assert json_response(conn, 403) == %{"error" => "Forbidden"}
    end

    test "returns 404 when project does not exist", %{conn: conn, user: _user} do
      non_existent_id = Ecto.UUID.generate()

      conn = get(conn, ~p"/api/projects/#{non_existent_id}/credentials")
      assert json_response(conn, 404) == %{"error" => "Not Found"}
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

    test "fails when user lacks access to project", %{conn: conn, user: _user} do
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

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      assert json_response(conn, 403) == %{"error" => "Forbidden"}
    end

    test "fails when user has insufficient role (viewer) on project", %{
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

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      assert json_response(conn, 403) == %{"error" => "Forbidden"}
    end

    test "fails when project does not exist", %{conn: conn, user: _user} do
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

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      assert json_response(conn, 403) == %{"error" => "Forbidden"}
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

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      response = json_response(conn, 422)

      assert %{"errors" => errors} = response
      assert Map.has_key?(errors, "name")
    end

    test "fails when missing required fields", %{conn: conn, user: _user} do
      credential_attrs = %{
        "name" => ""
      }

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      response = json_response(conn, 422)

      assert %{"errors" => _errors} = response
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

    test "handles partial project access - allows accessible, denies inaccessible",
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
          %{"project_id" => accessible_project.id},
          %{"project_id" => inaccessible_project.id}
        ]
      }

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      assert json_response(conn, 403) == %{"error" => "Forbidden"}
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
      assert json_response(conn, 404) == %{"error" => "Not Found"}
    end

    test "returns 403 when trying to delete credential owned by another user", %{
      conn: conn,
      user: _user
    } do
      other_user = insert(:user)

      other_credential =
        insert(:credential,
          user: other_user,
          name: "Other User Credential",
          schema: "raw"
        )

      conn = delete(conn, ~p"/api/credentials/#{other_credential.id}")
      assert json_response(conn, 403) == %{"error" => "Forbidden"}

      # Verify credential still exists
      assert Lightning.Credentials.get_credential(other_credential.id)
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
      assert json_response(conn, 404) == %{"error" => "Not Found"}
    end
  end
end
