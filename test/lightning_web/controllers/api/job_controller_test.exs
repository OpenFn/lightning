defmodule LightningWeb.API.JobControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.JobsFixtures

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    setup [:assign_bearer_for_api, :create_project_for_current_user, :create_job]

    test "lists all jobs for project", %{conn: conn, job: job} do
      conn = get(conn, Routes.api_project_job_path(conn, :index, job.project_id))
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

    test "lists all jobs", %{conn: conn, job: job} do
      conn = get(conn, Routes.api_job_path(conn, :index))
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

    test "shows the job", %{conn: conn, job: job} do
      conn = get(conn, Routes.api_job_path(conn, :show, job))
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
    %{job: job_fixture(project_id: project.id)}
  end
end
