defmodule LightningWeb.API.RunControllerTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.ApiReadHelpers

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

    test "a caller without permission gets the same 403 whether or not the run exists, and a permitted one 404 or 400",
         %{conn: member, project: project} do
      for {caller, path, status, code, entries} <-
            who_may_read(member, project, "runs", &insert_run/1) do
        caller |> get(path) |> assert_problem(status, code, entries)
      end
    end
  end
end
