defmodule LightningWeb.API.WorkOrders.CancellingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.HistoryHelpers
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers

  alias Lightning.RaceHelpers
  alias Lightning.Repo

  setup %{conn: conn} do
    context = history_callers(conn)
    graph = runnable_workflow(context.project)

    Map.merge(context, %{graph: graph, work_order: pending_work_order(graph)})
  end

  describe "cancelling" do
    test "a session token cancels a work order's waiting runs, and gets the work order back",
         %{work_order: work_order, editor_user: editor} do
      conn =
        build_conn()
        |> session_conn(editor)
        |> patch(~p"/api/work_orders/#{work_order.id}", %{state: "cancelled"})

      cancelled = Repo.reload!(work_order)
      url = "#{LightningWeb.Endpoint.url()}/api/work_orders/#{work_order.id}"

      assert json_response(conn, 200) == %{
               "data" => %{
                 "type" => "work_orders",
                 "id" => work_order.id,
                 "attributes" => %{
                   "state" => "cancelled",
                   "last_activity" =>
                     DateTime.to_iso8601(cancelled.last_activity),
                   "inserted_at" => DateTime.to_iso8601(cancelled.inserted_at),
                   "updated_at" => DateTime.to_iso8601(cancelled.updated_at)
                 },
                 "relationships" => %{},
                 "links" => %{"self" => url}
               },
               "included" => [],
               "links" => %{"self" => url}
             }

      assert Repo.reload!(hd(work_order.runs)).state == :cancelled
    end

    test "a personal access token cancels one too", %{
      editor: editor,
      work_order: work_order
    } do
      conn =
        patch(editor, ~p"/api/work_orders/#{work_order.id}", %{
          state: "cancelled"
        })

      assert json_response(conn, 200)["data"]["attributes"]["state"] ==
               "cancelled"
    end
  end

  describe "refusals" do
    test "a body that doesn't ask for cancelled is 422, and the run keeps waiting",
         %{editor: editor, work_order: work_order} do
      for {body, entries} <- [
            {%{}, [state_entry("required", "can't be blank")]},
            {%{state: "failed"},
             [state_entry("not_allowed", "must be cancelled")]},
            {%{state: "cancelled", reason: "x"},
             [
               %{
                 "pointer" => "#/reason",
                 "code" => "unknown_key",
                 "detail" => "is not accepted"
               }
             ]}
          ] do
        editor
        |> patch(~p"/api/work_orders/#{work_order.id}", body)
        |> assert_problem(422, :invalid, entries)
      end

      editor
      |> patch(~p"/api/work_orders/#{work_order.id}", Jason.encode!(1))
      |> assert_problem(400, :malformed, [])

      assert Repo.reload!(hd(work_order.runs)).state == :available
    end

    test "a work order with no run waiting for a worker is 422 not_allowed", %{
      editor: editor,
      graph: graph
    } do
      work_order = pending_work_order(graph, run_state: :started)

      editor
      |> patch(~p"/api/work_orders/#{work_order.id}", %{state: "cancelled"})
      |> assert_problem(422, :invalid, [
        state_entry(
          "not_allowed",
          "can't be set on a work order with no run waiting for a worker"
        )
      ])

      assert Repo.reload!(hd(work_order.runs)).state == :started
    end
  end

  describe "stale writes" do
    test "a work order whose run a worker claims after it was read is 409 concurrent_edit, and the run stays claimed",
         %{editor: editor, work_order: work_order} do
      run = hd(work_order.runs)

      # The work order's runs are read after the work order itself.
      RaceHelpers.after_first_query("runs", work_order.id, fn _id ->
        Repo.query!("UPDATE runs SET state = 'claimed' WHERE id = $1", [
          Ecto.UUID.dump!(run.id)
        ])
      end)

      editor
      |> patch(~p"/api/work_orders/#{work_order.id}", %{state: "cancelled"})
      |> assert_problem(409, :concurrent_edit, [])

      assert Repo.reload!(run).state == :claimed
    end
  end

  defp state_entry(code, detail),
    do: %{"pointer" => "#/state", "code" => code, "detail" => detail}
end
