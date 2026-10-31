defmodule LightningWeb.API.ProjectControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "without a token" do
    test "gets a 401", %{conn: conn} do
      conn = get(conn, ~p"/api/projects")
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "with invalid token" do
    test "gets a 401", %{conn: conn} do
      token = "Oooops"
      conn = conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      conn = get(conn, ~p"/api/projects")
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  # Proves the plug is wired into the /api scope, rather than only that the
  # plug function itself refuses — see user_auth_test.exs for the unit tests.
  describe "with an account past its confirmation deadline" do
    test "gets a 401, and the same token works again once confirmed", %{
      conn: conn
    } do
      Mox.stub(Lightning.MockConfig, :check_flag?, fn
        :require_email_verification -> true
        flag -> Lightning.Config.API.check_flag?(flag)
      end)

      user = insert(:user)
      insert(:project, project_users: [%{user: user}])

      token = Lightning.Accounts.generate_api_token(user)

      user =
        user
        |> Ecto.Changeset.change(
          confirmed_at: nil,
          inserted_at:
            DateTime.utc_now()
            |> DateTime.add(-50, :hour)
            |> DateTime.truncate(:second)
        )
        |> Lightning.Repo.update!()

      refused = conn |> assign_bearer(token) |> get(~p"/api/projects")

      assert json_response(refused, 401) == %{"error" => "Unauthorized"}

      user
      |> Ecto.Changeset.change(
        confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )
      |> Lightning.Repo.update!()

      allowed = conn |> assign_bearer(token) |> get(~p"/api/projects")

      assert [%{"type" => "projects"}] = json_response(allowed, 200)["data"]
    end
  end

  describe "index" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "lists all projects i belong to", %{conn: conn, project: project} do
      conn = get(conn, ~p"/api/projects")
      response = json_response(conn, 200)

      assert response["data"] == [
               %{
                 "attributes" => %{
                   "name" => project.name,
                   "description" => nil
                 },
                 "id" => project.id,
                 "links" => %{
                   "self" =>
                     "#{LightningWeb.Endpoint.url()}/api/projects/#{project.id}"
                 },
                 "relationships" => %{},
                 "type" => "projects"
               }
             ]
    end

    test "Other user don't have access to user project", %{
      conn: conn,
      project: project
    } do
      other_user = insert(:user)

      token =
        other_user
        |> Lightning.Accounts.generate_api_token()

      conn = conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")

      insert(:project, project_users: [%{user_id: other_user.id}])

      conn = get(conn, ~p"/api/projects")
      response = json_response(conn, 200)

      refute response["data"] == [
               %{
                 "attributes" => %{"name" => "a-test-project"},
                 "id" => project.id,
                 "links" => %{
                   "self" =>
                     "#{LightningWeb.Endpoint.url()}/api/projects/#{project.id}"
                 },
                 "relationships" => %{},
                 "type" => "projects"
               }
             ]
    end
  end

  describe "show" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "returns 404 for non-existent project", %{conn: conn} do
      conn = get(conn, ~p"/api/projects/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end

    test "with token for other project", %{conn: conn} do
      other_project = insert(:project)
      conn = get(conn, ~p"/api/projects/#{other_project.id}")
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end

    test "shows the project", %{conn: conn, project: project} do
      conn = get(conn, Routes.api_project_path(conn, :show, project))
      response = json_response(conn, 200)

      assert response["data"] == %{
               "attributes" => %{
                 "name" => project.name,
                 "description" => nil
               },
               "id" => project.id,
               "links" => %{
                 "self" =>
                   "#{LightningWeb.Endpoint.url()}/api/projects/#{project.id}"
               },
               "relationships" => %{},
               "type" => "projects"
             }
    end
  end
end
