defmodule LightningWeb.API.CredentialControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "without a token" do
    test "gets a 401", %{conn: conn} do
      conn = post(conn, ~p"/api/credentials", %{})
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "with invalid token" do
    test "gets a 401", %{conn: conn} do
      token = "InvalidToken"
      conn = conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      conn = post(conn, ~p"/api/credentials", %{})
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "create" do
    setup [:assign_bearer_for_api]

    test "creates a basic credential without project associations", %{conn: conn, user: user} do
      credential_attrs = %{
        "name" => "Test Credential",
        "body" => %{"username" => "test", "password" => "secret"},
        "schema" => "raw"
      }

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      response = json_response(conn, 201)

      assert %{
        "credential" => %{
          "id" => id,
          "name" => "Test Credential",
          "schema" => "raw",
          "production" => false,
          "external_id" => nil,
          "user_id" => user_id,
          "project_credentials" => [],
          "projects" => []
        },
        "errors" => %{}
      } = response

      assert is_binary(id)
      assert user_id == user.id
      refute Map.has_key?(response["credential"], "body")  # body should be excluded
    end

    test "creates a credential with project associations when user has access", %{conn: conn, user: user} do
      project = insert(:project, project_users: [%{user_id: user.id, role: :editor}])

      credential_attrs = %{
        "name" => "Project Credential",
        "body" => %{"api_key" => "secret"},
        "schema" => "raw",
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

    test "creates a credential with multiple project associations", %{conn: conn, user: user} do
      project1 = insert(:project, project_users: [%{user_id: user.id, role: :admin}])
      project2 = insert(:project, project_users: [%{user_id: user.id, role: :owner}])

      credential_attrs = %{
        "name" => "Multi-Project Credential",
        "body" => %{"token" => "abc123"},
        "schema" => "raw",
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

    test "fails when user lacks access to project", %{conn: conn, user: _user} do
      other_user = insert(:user)
      project = insert(:project, project_users: [%{user_id: other_user.id, role: :owner}])

      credential_attrs = %{
        "name" => "Unauthorized Credential",
        "body" => %{"secret" => "value"},
        "schema" => "raw",
        "project_credentials" => [
          %{"project_id" => project.id}
        ]
      }

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      assert json_response(conn, 403) == %{"error" => "Forbidden"}
    end

    test "fails when user has insufficient role (viewer) on project", %{conn: conn, user: user} do
      project = insert(:project, project_users: [%{user_id: user.id, role: :viewer}])

      credential_attrs = %{
        "name" => "Viewer Credential",
        "body" => %{"secret" => "value"},
        "schema" => "raw",
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
        "body" => %{"secret" => "value"},
        "schema" => "raw",
        "project_credentials" => [
          %{"project_id" => Ecto.UUID.generate()}
        ]
      }

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      assert json_response(conn, 403) == %{"error" => "Forbidden"}
    end

    test "allows access when user is support user with project access", %{conn: conn} do
      support_user = insert(:user, support_user: true)
      project = insert(:project, allow_support_access: true)

      token = Lightning.Accounts.generate_api_token(support_user)
      conn = conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")

      credential_attrs = %{
        "name" => "Support User Credential",
        "body" => %{"secret" => "value"},
        "schema" => "raw",
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
        "name" => "",  # Invalid: empty name
        "body" => %{"secret" => "value"},
        "schema" => "raw"
      }

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      response = json_response(conn, 422)

      assert %{"errors" => errors} = response
      assert Map.has_key?(errors, "name")
    end

    test "fails when missing required fields", %{conn: conn, user: _user} do
      credential_attrs = %{
        "name" => "Test"
        # Missing body and schema
      }

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      response = json_response(conn, 422)

      assert %{"errors" => errors} = response
      assert Map.has_key?(errors, "body")
    end

    test "cannot override user_id in request", %{conn: conn, user: user} do
      other_user = insert(:user)

      credential_attrs = %{
        "name" => "Test Credential",
        "body" => %{"secret" => "value"},
        "schema" => "raw",
        "user_id" => other_user.id  # This should be ignored
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
        "body" => %{"secret" => "value"},
        "schema" => "raw"
      }

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      assert json_response(conn, 201)
    end

    test "handles partial project access - allows accessible, denies inaccessible", %{conn: conn, user: user} do
      accessible_project = insert(:project, project_users: [%{user_id: user.id, role: :editor}])
      inaccessible_project = insert(:project)  # No user access

      credential_attrs = %{
        "name" => "Mixed Access Credential",
        "body" => %{"secret" => "value"},
        "schema" => "raw",
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
      project = insert(:project, project_users: [%{user_id: user.id, role: :editor}])

      credential_attrs = %{
        "name" => "Editor Credential",
        "body" => %{"secret" => "value"},
        "schema" => "raw",
        "project_credentials" => [%{"project_id" => project.id}]
      }

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      assert json_response(conn, 201)
    end
  end

  describe "admin role permissions" do
    setup [:assign_bearer_for_api]

    test "admin can create project credentials", %{conn: conn, user: user} do
      project = insert(:project, project_users: [%{user_id: user.id, role: :admin}])

      credential_attrs = %{
        "name" => "Admin Credential",
        "body" => %{"secret" => "value"},
        "schema" => "raw",
        "project_credentials" => [%{"project_id" => project.id}]
      }

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      assert json_response(conn, 201)
    end
  end

  describe "owner role permissions" do
    setup [:assign_bearer_for_api]

    test "owner can create project credentials", %{conn: conn, user: user} do
      project = insert(:project, project_users: [%{user_id: user.id, role: :owner}])

      credential_attrs = %{
        "name" => "Owner Credential",
        "body" => %{"secret" => "value"},
        "schema" => "raw",
        "project_credentials" => [%{"project_id" => project.id}]
      }

      conn = post(conn, ~p"/api/credentials", credential_attrs)
      assert json_response(conn, 201)
    end
  end
end
