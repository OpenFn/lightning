defmodule LightningWeb.API.WorkOrders.CancellingManyTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.HistoryHelpers
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers

  alias Lightning.Repo

  setup %{conn: conn} do
    context = history_callers(conn)
    graph = runnable_workflow(context.project)

    Map.merge(context, %{
      graph: graph,
      first: pending_work_order(graph),
      second: pending_work_order(graph),
      running: pending_work_order(graph, run_state: :started),
      path: ~p"/api/projects/#{context.project.id}/work_orders/cancellations"
    })
  end

  describe "cancelling" do
    test "a session token cancels the waiting runs of every work order a filter matches, and hears how many work orders had one",
         %{path: path, editor_user: editor} = context do
      elsewhere = pending_work_order(runnable_workflow(insert(:project)))

      conn =
        build_conn()
        |> session_conn(editor)
        |> post(path, %{filter: %{workflow_id: context.graph.workflow.id}})

      assert json_response(conn, 202) == %{"cancelled" => 2}

      assert Enum.map(
               [context.first, context.second, context.running, elsewhere],
               &run_state/1
             ) == [:cancelled, :cancelled, :started, :available]
    end

    test "a personal access token cancels listed work orders in the request, and one outside the project is not counted",
         %{path: path, editor: editor, first: first, second: second} do
      elsewhere = pending_work_order(runnable_workflow(insert(:project)))

      conn = post(editor, path, %{work_order_ids: [first.id, elsewhere.id]})

      assert json_response(conn, 202) == %{"cancelled" => 1}

      assert Enum.map([first, second, elsewhere], &run_state/1) == [
               :cancelled,
               :available,
               :available
             ]
    end
  end

  describe "refusals" do
    test "a body that selects nothing, both ways, or takes another key is 422, and nothing is cancelled",
         %{path: path, editor: editor, first: first} do
      for {body, entries} <- [
            {%{},
             [entry("/filter", "required", "send filter or work_order_ids")]},
            {%{filter: %{}, work_order_ids: [first.id]},
             [entry("/work_order_ids", "exclusive", "can't be sent with filter")]},
            {%{work_order_ids: [first.id], job_id: first.id},
             [entry("/job_id", "unknown_key", "is not accepted")]},
            {%{filter: %{state: "sideways"}},
             [entry("/filter/state", "not_allowed", "has an invalid entry")]}
          ] do
        editor
        |> post(path, body)
        |> assert_problem(422, :invalid, entries)
      end

      editor
      |> post(path, Jason.encode!("all"))
      |> assert_problem(400, :malformed, [])

      assert run_state(first) == :available
    end
  end

  defp entry(pointer, code, detail),
    do: %{"pointer" => "#" <> pointer, "code" => code, "detail" => detail}

  defp run_state(work_order), do: Repo.reload!(hd(work_order.runs)).state
end
