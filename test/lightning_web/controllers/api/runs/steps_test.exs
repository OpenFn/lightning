defmodule LightningWeb.API.Runs.StepsTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.HistoryHelpers
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers

  setup %{conn: conn} do
    context = history_callers(conn)
    graph = runnable_workflow(context.project)

    Map.merge(context, Map.put(ran_work_order(graph), :graph, graph))
  end

  describe "reading" do
    test "a session token reads a run's steps in the order they ran", %{
      run: run,
      step_a: step_a,
      step_b: step_b,
      editor_user: editor
    } do
      conn =
        build_conn()
        |> session_conn(editor)
        |> get(~p"/api/runs/#{run.id}/steps")

      assert json_response(conn, 200) == %{
               "data" => [
                 %{
                   "type" => "steps",
                   "id" => step_a.id,
                   "attributes" => %{
                     "job_id" => step_a.job_id,
                     "exit_reason" => "success",
                     "error_type" => nil,
                     "started_at" => "2024-01-01T10:00:00.000000Z",
                     "finished_at" => "2024-01-01T10:00:01.000000Z",
                     "input_dataclip_id" => step_a.input_dataclip_id,
                     "output_dataclip_id" => nil
                   },
                   "relationships" => %{},
                   "links" => %{}
                 },
                 %{
                   "type" => "steps",
                   "id" => step_b.id,
                   "attributes" => %{
                     "job_id" => step_b.job_id,
                     "exit_reason" => "fail",
                     "error_type" => "RuntimeError",
                     "started_at" => "2024-01-01T10:00:02.000000Z",
                     "finished_at" => "2024-01-01T10:00:03.000000Z",
                     "input_dataclip_id" => step_b.input_dataclip_id,
                     "output_dataclip_id" => nil
                   },
                   "relationships" => %{},
                   "links" => %{}
                 }
               ],
               "included" => [],
               "links" => %{
                 "self" =>
                   "#{LightningWeb.Endpoint.url()}/api/runs/#{run.id}/steps"
               }
             }
    end

    test "a viewer's personal access token narrows them to one job's", %{
      viewer: viewer,
      run: run,
      step_b: step_b
    } do
      conn =
        get(viewer, ~p"/api/runs/#{run.id}/steps?#{%{job_id: step_b.job_id}}")

      assert Enum.map(json_response(conn, 200)["data"], & &1["id"]) == [
               step_b.id
             ]
    end

    test "a job_id that isn't a UUID is 400 invalid_parameter", %{
      viewer: viewer,
      run: run
    } do
      for query <- ["job_id=not-a-uuid", "job_id[]=x"] do
        viewer
        |> get("/api/runs/#{run.id}/steps?#{query}")
        |> assert_problem(400, :invalid_parameter, [
          not_a_uuid_entry(%{"parameter" => "job_id"})
        ])
      end
    end
  end
end
