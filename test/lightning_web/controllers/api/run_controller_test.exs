defmodule LightningWeb.API.RunControllerTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.ApiReadHelpers
  import Lightning.Factories

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "show" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "answers the run, and links to it without the request's query", %{
      conn: conn,
      project: project
    } do
      run =
        insert_run(project,
          state: :success,
          started_at: ~U[2024-01-01 10:00:00.000000Z],
          finished_at: ~U[2024-01-01 10:05:00.000000Z]
        )

      assert conn |> get(~p"/api/runs/#{run.id}?foo=bar") |> json_response(200) ==
               %{
                 "data" => %{
                   "type" => "runs",
                   "id" => run.id,
                   "relationships" => %{},
                   "links" => %{
                     "self" =>
                       "#{LightningWeb.Endpoint.url()}/api/runs/#{run.id}"
                   },
                   "attributes" => %{
                     "state" => "success",
                     "started_at" => "2024-01-01T10:00:00.000000Z",
                     "finished_at" => "2024-01-01T10:05:00.000000Z",
                     "priority" => "normal",
                     "error_type" => nil
                   }
                 },
                 "included" => [],
                 "links" => %{
                   "self" => "#{LightningWeb.Endpoint.url()}/api/runs/#{run.id}"
                 }
               }
    end
  end

  describe "who may reach it" do
    setup [:assign_bearer_for_api, :create_project_for_current_user]

    test "answers 404 for what the caller has no standing on or that is missing, before the query is read, and 403 to a member who has not met the MFA requirement",
         %{conn: conn, project: project} do
      own = insert_run(project)
      elsewhere = insert(:project)
      unseen = insert_run(elsewhere)
      Lightning.Repo.update!(Ecto.Changeset.change(project, requires_mfa: true))

      for {path, status, code} <- [
            {~p"/api/projects/#{elsewhere.id}/runs?state=sideways", 404,
             :not_found},
            {~p"/api/projects/#{Ecto.UUID.generate()}/runs", 404, :not_found},
            {~p"/api/runs/#{unseen.id}", 404, :not_found},
            {~p"/api/runs/#{Ecto.UUID.generate()}", 404, :not_found},
            {~p"/api/runs/#{own.id}", 403, :forbidden}
          ] do
        conn |> get(path) |> assert_problem(status, code, [])
      end
    end
  end
end
