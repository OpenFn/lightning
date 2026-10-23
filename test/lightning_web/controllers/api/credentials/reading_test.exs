defmodule LightningWeb.API.Credentials.ReadingTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Lightning.QueryCountHelpers
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.ApiCredentialsHelpers
  import Lightning.ServiceAccountHelpers

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "listing what the caller owns" do
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

  describe "listing a project's credentials" do
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

    test "answers 404 for a project the caller isn't a member of, or that doesn't exist",
         %{conn: conn} do
      project =
        insert(:project,
          project_users: [%{user_id: insert(:user).id, role: :owner}]
        )

      for id <- [project.id, Ecto.UUID.generate()] do
        conn
        |> get(~p"/api/projects/#{id}/credentials")
        |> assert_problem(404, :not_found, [])
      end
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

  describe "showing one credential" do
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
                 "projects" => []
               },
               "errors" => %{}
             } = response = json_response(conn, 200)

      assert {id, user_id} == {credential.id, owner.id}
      assert linked_project_ids(response) == [project.id]
      refute conn.resp_body =~ "password"

      conn
      |> get(~p"/api/credentials/#{Ecto.UUID.generate()}")
      |> assert_problem(404, :not_found, [])
    end

    test "a service account also holding projects:write sees the projects by name",
         %{conn: conn} do
      {conn, _account} =
        with_service_account(conn, ["credentials:write", "projects:write"])

      project = insert(:project)
      credential = existing_credential(insert(:user), project)

      response =
        conn
        |> get(~p"/api/credentials/#{credential.id}")
        |> json_response(200)

      assert [%{"id" => project_id}] = response["credential"]["projects"]
      assert project_id == project.id
    end

    test "a person reads only their own, seeing links only to projects they stand in",
         %{conn: conn} do
      owner = insert(:user)
      theirs = insert(:project, project_users: [%{user: owner, role: :owner}])

      winding_down =
        insert(:project,
          project_users: [%{user: owner, role: :owner}],
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
        )

      credential = existing_credential(owner, theirs)

      for project <- [insert(:project), winding_down],
          do:
            insert(:project_credential, credential: credential, project: project)

      response =
        conn
        |> with_pat(owner)
        |> get(~p"/api/credentials/#{credential.id}")
        |> json_response(200)

      assert linked_project_ids(response) == [theirs.id]
      assert [%{"id" => theirs_id}] = response["credential"]["projects"]
      assert theirs_id == theirs.id

      conn
      |> with_pat(insert(:user))
      |> get(~p"/api/credentials/#{credential.id}")
      |> assert_problem(404, :not_found, [])
    end

    test "a person reads someone else's credential linked to a project they stand in",
         %{conn: conn} do
      viewer = insert(:user)
      shared = insert(:project, project_users: [%{user: viewer, role: :viewer}])
      credential = existing_credential(insert(:user), shared)

      insert(:project_credential,
        credential: credential,
        project: insert(:project)
      )

      response =
        conn
        |> with_pat(viewer)
        |> get(~p"/api/credentials/#{credential.id}")
        |> json_response(200)

      assert response["credential"]["id"] == credential.id
      assert linked_project_ids(response) == [shared.id]
      refute Jason.encode!(response) =~ "password"
    end
  end

  test "GET costs the same number of queries however many projects it links",
       %{conn: conn} do
    owner = insert(:user)

    [first | rest] =
      insert_list(3, :project, project_users: [%{user: owner, role: :owner}])

    credential = existing_credential(owner, first)
    conn = with_pat(conn, owner)

    show = fn ->
      conn |> get(~p"/api/credentials/#{credential.id}") |> json_response(200)
    end

    {_, one_link} = count_queries(show)

    for project <- rest,
        do: insert(:project_credential, credential: credential, project: project)

    assert {_, ^one_link} = count_queries(show)
  end
end
