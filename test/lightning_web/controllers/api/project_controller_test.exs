defmodule LightningWeb.API.ProjectControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.ProjectsFixtures

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "without a token" do
    test "gets a 401", %{conn: conn} do
      conn = get(conn, Routes.api_project_path(conn, :index))
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "index" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "with token for other project", %{conn: conn} do
      other_project = project_fixture()
      conn = get(conn, Routes.api_project_path(conn, :show, other_project.id))
      assert json_response(conn, 403) == %{"error" => "Forbidden"}
    end

    test "lists all projects", %{conn: conn, project: project} do
      conn = get(conn, Routes.api_project_path(conn, :index))
      response = json_response(conn, 200)

      assert response["data"] == [
               %{
                 "attributes" => %{"name" => "some-name"},
                 "id" => project.id,
                 "links" => %{
                   "self" => "http://localhost:4002/api/projects/#{project.id}"
                 },
                 "relationships" => %{},
                 "type" => "projects"
               }
             ]
    end
  end

  describe "show" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "with token for other project", %{conn: conn} do
      other_project = project_fixture()
      conn = get(conn, Routes.api_project_path(conn, :show, other_project.id))
      assert json_response(conn, 403) == %{"error" => "Forbidden"}
    end

    test "shows the project", %{conn: conn, project: project} do
      conn = get(conn, Routes.api_project_path(conn, :show, project))
      response = json_response(conn, 200)

      assert response["data"] == %{
               "attributes" => %{"name" => "some-name"},
               "id" => project.id,
               "links" => %{
                 "self" => "http://localhost:4002/api/projects/#{project.id}"
               },
               "relationships" => %{},
               "type" => "projects"
             }
    end
  end
end
