defmodule LightningWeb.API.Runs.CancellingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.HistoryHelpers
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers

  alias Lightning.RaceHelpers
  alias Lightning.Repo
  alias Lightning.Run

  setup %{conn: conn} do
    context = history_callers(conn)
    graph = runnable_workflow(context.project)
    work_order = pending_work_order(graph)

    Map.merge(context, %{graph: graph, run: hd(work_order.runs)})
  end

  describe "cancelling" do
    test "a session token cancels a run no worker has claimed, and gets the run back",
         %{run: run, editor_user: editor} do
      conn =
        build_conn()
        |> session_conn(editor)
        |> patch(~p"/api/runs/#{run.id}", %{state: "cancelled"})

      assert json_response(conn, 200) == %{
               "data" => %{
                 "type" => "runs",
                 "id" => run.id,
                 "relationships" => %{},
                 "links" => %{
                   "self" => "#{LightningWeb.Endpoint.url()}/api/runs/#{run.id}"
                 },
                 "attributes" => %{
                   "state" => "cancelled",
                   "started_at" => nil,
                   "finished_at" => nil,
                   "priority" => "normal",
                   "error_type" => nil
                 }
               },
               "included" => [],
               "links" => %{
                 "self" => "#{LightningWeb.Endpoint.url()}/api/runs/#{run.id}"
               }
             }

      assert Repo.reload!(run).state == :cancelled
    end

    test "a personal access token cancels it too", %{editor: editor, run: run} do
      conn = patch(editor, ~p"/api/runs/#{run.id}", %{state: "cancelled"})

      assert json_response(conn, 200)["data"]["attributes"]["state"] ==
               "cancelled"
    end
  end

  describe "refusals" do
    test "a body that doesn't ask for cancelled is 422 with every problem, and the run is left waiting",
         %{editor: editor, run: run} do
      for {body, entries} <- [
            {%{}, [required_state()]},
            {%{state: "success"},
             [
               %{
                 "pointer" => "#/state",
                 "code" => "not_allowed",
                 "detail" => "must be cancelled"
               }
             ]},
            {%{state: "cancelled", priority: "immediate"},
             [
               %{
                 "pointer" => "#/priority",
                 "code" => "unknown_key",
                 "detail" => "is not accepted"
               }
             ]}
          ] do
        editor
        |> patch(~p"/api/runs/#{run.id}", body)
        |> assert_problem(422, :invalid, entries)
      end

      assert Repo.reload!(run).state == :available
    end

    test "a body that isn't a JSON object is 400 malformed", %{
      editor: editor,
      run: run
    } do
      editor
      |> patch(~p"/api/runs/#{run.id}", Jason.encode!(["cancelled"]))
      |> assert_problem(400, :malformed, [])
    end

    test "a run a worker has claimed, or that has finished, is 422 not_allowed and is left as it was",
         %{editor: editor, graph: graph} do
      for state <- [:claimed, :started, :success, :cancelled] do
        %{runs: [run]} = pending_work_order(graph, run_state: state)

        editor
        |> patch(~p"/api/runs/#{run.id}", %{state: "cancelled"})
        |> assert_problem(422, :invalid, [
          %{
            "pointer" => "#/state",
            "code" => "not_allowed",
            "detail" => "can't be set once a worker claims the run"
          }
        ])

        assert Repo.reload!(run).state == state
      end
    end
  end

  describe "stale writes" do
    test "a run a worker claims after it was read is 409 concurrent_edit, and stays claimed",
         %{editor: editor, run: run} do
      # The first query finds the run's project, the second reads the run.
      RaceHelpers.after_first_query("runs", run.id, fn _id ->
        RaceHelpers.after_first_query("runs", run.id, fn id ->
          Repo.query!("UPDATE runs SET state = 'claimed' WHERE id = $1", [id])
        end)
      end)

      editor
      |> patch(~p"/api/runs/#{run.id}", %{state: "cancelled"})
      |> assert_problem(409, :concurrent_edit, [])

      assert %Run{state: :claimed} = Repo.reload!(run)
    end
  end

  defp required_state,
    do: %{
      "pointer" => "#/state",
      "code" => "required",
      "detail" => "can't be blank"
    }
end
