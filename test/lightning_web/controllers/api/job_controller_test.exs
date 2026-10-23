defmodule LightningWeb.API.JobControllerTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import Lightning.Factories
  import Lightning.JobsFixtures

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "index" do
    setup [:assign_bearer_for_api, :create_project_for_current_user, :create_job]

    test "lists the project's jobs, on the nested route and the plain one", %{
      conn: conn,
      job: job
    } do
      for path <- [
            ~p"/api/projects/#{job.workflow.project_id}/jobs",
            ~p"/api/jobs"
          ] do
        assert conn |> get(path) |> json_response(200) |> Map.fetch!("data") == [
                 %{
                   "attributes" => %{"name" => "some name"},
                   "id" => job.id,
                   "links" => %{
                     "self" =>
                       "#{LightningWeb.Endpoint.url()}/api/jobs/#{job.id}"
                   },
                   "relationships" => %{},
                   "type" => "jobs"
                 }
               ]
      end
    end

    test "reads the number a page param starts with, and falls back to the default for one it can't read",
         %{conn: conn, project: project} do
      workflow = insert(:workflow, project: project)
      insert_list(11, :job, workflow: workflow)

      for {query, entries, page} <- [
            {"page=5abc&page_size=2.0", 2, %{"page" => "5", "page_size" => "2"}},
            {"page=abc&page_size=xyz", 10,
             %{"page" => "1", "page_size" => "10"}},
            {"page[]=2&page_size[]=2", 10,
             %{"page" => "1", "page_size" => "10"}},
            {"page=-1&page_size=0", 10, %{"page" => "1", "page_size" => "10"}}
          ] do
        assert %{"data" => data, "links" => %{"self" => self}} =
                 conn |> get("/api/jobs?" <> query) |> json_response(200)

        assert {length(data), URI.decode_query(URI.parse(self).query)} ==
                 {entries, page},
               query
      end
    end

    test "pagination links carry the project filter applied and nothing else",
         %{conn: conn, project: project} do
      for {path, request_path, query} <- [
            {~p"/api/jobs?#{%{project_id: project.id, page_size: 1, foo: "bar"}}",
             "/api/jobs", %{"project_id" => project.id}},
            {~p"/api/projects/#{project.id}/jobs?page_size=1&foo=bar",
             "/api/projects/#{project.id}/jobs", %{}},
            {~p"/api/jobs?page_size=1&foo=bar", "/api/jobs", %{}}
          ] do
        %{"links" => links} = conn |> get(path) |> json_response(200)

        for key <- ["self", "first"] do
          uri = URI.parse(links[key])
          assert uri.path == request_path

          assert URI.decode_query(uri.query) ==
                   Map.merge(query, %{"page" => "1", "page_size" => "1"})
        end
      end
    end
  end

  describe "show" do
    setup [:assign_bearer_for_api, :create_project_for_current_user, :create_job]

    test "answers the job, and links to it without the request's query", %{
      conn: conn,
      job: job
    } do
      url = "#{LightningWeb.Endpoint.url()}/api/jobs/#{job.id}"

      assert conn |> get(~p"/api/jobs/#{job}?foo=bar") |> json_response(200) ==
               %{
                 "data" => %{
                   "attributes" => %{"name" => "some name"},
                   "id" => job.id,
                   "links" => %{"self" => url},
                   "relationships" => %{},
                   "type" => "jobs"
                 },
                 "included" => [],
                 "links" => %{"self" => url}
               }
    end
  end

  describe "who may reach it" do
    setup [:assign_bearer_for_api, :create_project_for_current_user, :create_job]

    test "answers 404 for what the caller has no standing on or that is missing, and 403 to a member who has not met the MFA requirement",
         %{conn: conn, project: project, job: job} do
      elsewhere = insert(:project)
      %{job: unseen} = create_job(%{project: elsewhere})
      Lightning.Repo.update!(Ecto.Changeset.change(project, requires_mfa: true))

      for {path, status, code} <- [
            {~p"/api/projects/#{elsewhere.id}/jobs", 404, :not_found},
            {~p"/api/projects/#{Ecto.UUID.generate()}/jobs", 404, :not_found},
            {~p"/api/jobs?#{%{project_id: elsewhere.id}}", 404, :not_found},
            {~p"/api/jobs/#{unseen.id}", 404, :not_found},
            {~p"/api/jobs/#{Ecto.UUID.generate()}", 404, :not_found},
            {~p"/api/jobs?#{%{project_id: project.id}}", 403, :forbidden},
            {~p"/api/jobs/#{job.id}", 403, :forbidden}
          ] do
        conn |> get(path) |> assert_problem(status, code, [])
      end
    end
  end

  defp create_job(%{project: project}) do
    %{job: job} = workflow_job_fixture(project_id: project.id)
    %{job: job}
  end
end
