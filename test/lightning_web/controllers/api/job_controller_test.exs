defmodule LightningWeb.API.JobControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.JobsFixtures
  import Lightning.ProjectsFixtures

  # Sample curl requests:
  #
  #   # List all jobs
  #   curl http://localhost:4000/api/jobs \
  #     -H "Authorization: Bearer $TOKEN" -H "Accept: application/json"
  #
  #   # Get a single job by ID
  #   curl http://localhost:4000/api/jobs/$JOB_ID \
  #     -H "Authorization: Bearer $TOKEN" -H "Accept: application/json"
  #
  #   # List jobs for a specific project
  #   curl http://localhost:4000/api/projects/$PROJECT_ID/jobs \
  #     -H "Authorization: Bearer $TOKEN" -H "Accept: application/json"

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  test "without a token", %{conn: conn} do
    conn = get(conn, ~p"/api/projects/#{Ecto.UUID.generate()}/jobs")

    assert %{"error" => "Unauthorized"} == json_response(conn, 401)
  end

  describe "with invalid token" do
    test "gets a 401", %{conn: conn} do
      token = "Oooops"
      conn = conn |> Plug.Conn.put_req_header("authorization", "Bearer #{token}")
      conn = get(conn, ~p"/api/projects/#{Ecto.UUID.generate()}/jobs")
      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "index" do
    setup [:assign_bearer_for_api, :create_project_for_current_user, :create_job]

    test "lists all jobs for project I belong to", %{conn: conn, job: job} do
      conn = get(conn, ~p"/api/projects/#{job.workflow.project_id}/jobs")

      response = json_response(conn, 200)

      assert response["data"] == [
               %{
                 "attributes" => %{"name" => "some name"},
                 "id" => job.id,
                 "links" => %{
                   "self" => "http://localhost:4002/api/jobs/#{job.id}"
                 },
                 "relationships" => %{},
                 "type" => "jobs"
               }
             ]
    end

    test "responds with a 401 when I don't have access", %{conn: conn} do
      other_project = project_fixture()

      conn = get(conn, ~p"/api/projects/#{other_project.id}/jobs")

      response = json_response(conn, 401)

      assert response == %{"error" => "Unauthorized"}
    end

    test "lists all jobs", %{conn: conn, job: job} do
      conn = get(conn, ~p"/api/jobs")
      response = json_response(conn, 200)

      assert response["data"] == [
               %{
                 "attributes" => %{"name" => "some name"},
                 "id" => job.id,
                 "links" => %{
                   "self" => "http://localhost:4002/api/jobs/#{job.id}"
                 },
                 "relationships" => %{},
                 "type" => "jobs"
               }
             ]
    end
  end

  describe "show" do
    setup [:assign_bearer_for_api, :create_project_for_current_user, :create_job]

    test "returns 404 for non-existent job", %{conn: conn} do
      conn = get(conn, ~p"/api/jobs/#{Ecto.UUID.generate()}")
      assert json_response(conn, 404)
    end

    test "shows the job", %{conn: conn, job: job} do
      conn = get(conn, ~p"/api/jobs/#{job}")
      response = json_response(conn, 200)

      assert response["data"] == %{
               "attributes" => %{"name" => "some name"},
               "id" => job.id,
               "links" => %{
                 "self" => "http://localhost:4002/api/jobs/#{job.id}"
               },
               "relationships" => %{},
               "type" => "jobs"
             }
    end
  end

  defp create_job(%{project: project}) do
    %{job: job} = workflow_job_fixture(project_id: project.id)
    %{job: job}
  end
end
