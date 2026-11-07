defmodule LightningWeb.API.WorkOrders.StartingTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.HistoryHelpers
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers

  import Ecto.Query

  alias Lightning.RaceHelpers
  alias Lightning.Repo
  alias Lightning.WorkOrder

  setup %{conn: conn} do
    context = history_callers(conn)
    Map.put(context, :graph, runnable_workflow(context.project))
  end

  defp path(graph),
    do:
      ~p"/api/projects/#{graph.workflow.project_id}/workflows/#{graph.workflow.id}/work_orders"

  describe "starting" do
    test "a session token starts a work order from a job with a new input, and gets it back with its ids in headers",
         %{graph: graph, editor_user: editor} do
      conn =
        build_conn()
        |> session_conn(editor)
        |> post(path(graph), %{job_id: graph.job_b.id, body: %{"patient" => "x"}})

      assert %{"data" => %{"id" => id}} = body = json_response(conn, 201)

      work_order =
        WorkOrder
        |> Repo.get!(id)
        |> Repo.preload([:dataclip, :runs])

      [run] = work_order.runs
      url = "#{LightningWeb.Endpoint.url()}/api/work_orders/#{id}"

      assert body == %{
               "data" => %{
                 "type" => "work_orders",
                 "id" => id,
                 "attributes" => %{
                   "state" => "pending",
                   "last_activity" =>
                     DateTime.to_iso8601(work_order.last_activity),
                   "inserted_at" => DateTime.to_iso8601(work_order.inserted_at),
                   "updated_at" => DateTime.to_iso8601(work_order.updated_at)
                 },
                 "relationships" => %{},
                 "links" => %{"self" => url}
               },
               "included" => [],
               "links" => %{"self" => url}
             }

      assert get_resp_header(conn, "x-meta-work-order-id") == [id]
      assert get_resp_header(conn, "x-meta-run-id") == [run.id]

      assert {body_of(work_order.dataclip_id), work_order.dataclip.type,
              run.starting_job_id, run.created_by_id, run.priority} ==
               {%{"patient" => "x"}, :saved_input, graph.job_b.id, editor.id,
                :immediate}
    end

    test "a personal access token starts one from a trigger's job, reusing an input",
         %{graph: graph, editor: editor} do
      dataclip = insert(:dataclip, project: graph.workflow.project)

      conn =
        post(editor, path(graph), %{
          trigger_id: graph.trigger.id,
          dataclip_id: dataclip.id
        })

      id = json_response(conn, 201)["data"]["id"]
      work_order = WorkOrder |> Repo.get!(id) |> Repo.preload(:runs)

      assert {work_order.dataclip_id, hd(work_order.runs).starting_job_id} ==
               {dataclip.id, graph.job_a.id}
    end

    test "with neither body nor dataclip_id, the input is {}", %{
      graph: graph,
      editor: editor
    } do
      conn = post(editor, path(graph), %{job_id: graph.job_a.id})

      id = json_response(conn, 201)["data"]["id"]

      assert body_of(Repo.get!(WorkOrder, id).dataclip_id) == %{}
    end
  end

  describe "refusals" do
    test "a body that names no start, two, one outside the workflow, or two inputs is 422 with every problem, and nothing starts",
         %{graph: graph, editor: editor} do
      other = runnable_workflow(graph.workflow.project)
      elsewhere = insert(:dataclip)

      for {body, entries} <- [
            {%{}, [entry("job_id", "required", "send job_id or trigger_id")]},
            {%{job_id: graph.job_a.id, trigger_id: graph.trigger.id},
             [entry("trigger_id", "exclusive", "can't be sent with job_id")]},
            {%{job_id: other.job_a.id},
             [entry("job_id", "not_found", "is not in this workflow")]},
            {%{trigger_id: other.trigger.id},
             [entry("trigger_id", "not_found", "is not in this workflow")]},
            {%{job_id: "not-a-uuid", dataclip_id: 3},
             [
               entry("job_id", "type", "is not a UUID"),
               entry("dataclip_id", "type", "is not a UUID")
             ]},
            {%{job_id: graph.job_a.id, dataclip_id: elsewhere.id, body: %{}},
             [entry("body", "exclusive", "can't be sent with dataclip_id")]},
            {%{job_id: graph.job_a.id, dataclip_id: elsewhere.id},
             [entry("dataclip_id", "not_found", "names nothing you can see")]},
            {%{job_id: graph.job_a.id, body: [1], name: "x"},
             [
               entry("body", "type", "must be an object"),
               entry("name", "unknown_key", "is not accepted")
             ]}
          ] do
        editor
        |> post(path(graph), body)
        |> assert_problem(422, :invalid, entries)
      end

      assert Repo.aggregate(WorkOrder, :count) == 0
    end

    test "a wiped input is 422 dataclip_wiped", %{graph: graph, editor: editor} do
      wiped =
        insert(:dataclip,
          project: graph.workflow.project,
          wiped_at: DateTime.utc_now(),
          body: nil
        )

      editor
      |> post(path(graph), %{job_id: graph.job_a.id, dataclip_id: wiped.id})
      |> assert_problem(422, :invalid, [
        entry("dataclip_id", "dataclip_wiped", "has been wiped")
      ])
    end

    test "a body that isn't a JSON object is 400 malformed", %{
      graph: graph,
      editor: editor
    } do
      editor
      |> post(path(graph), Jason.encode!("run"))
      |> assert_problem(400, :malformed, [])
    end

    test "the run limits are asked once the body is valid", %{
      graph: graph,
      editor: editor
    } do
      for {reason, status, code} <- run_limit_refusals() do
        limit_runs(reason)

        editor
        |> post(path(graph), %{job_id: graph.job_a.id})
        |> assert_problem(status, code, [])

        editor
        |> post(path(graph), %{})
        |> assert_problem(422, :invalid, [
          entry("job_id", "required", "send job_id or trigger_id")
        ])
      end

      assert Repo.aggregate(WorkOrder, :count) == 0
    end
  end

  describe "stale writes" do
    test "a workflow another request deletes mid-start answers 409 concurrent_edit, and no work order is made",
         %{graph: graph, editor: editor} do
      RaceHelpers.after_first_query("workflows", graph.workflow.id, fn id ->
        Repo.query!("UPDATE workflows SET deleted_at = now() WHERE id = $1", [id])
      end)

      editor
      |> post(path(graph), %{job_id: graph.job_a.id})
      |> assert_problem(409, :concurrent_edit, [])

      assert {Repo.aggregate(WorkOrder, :count),
              not is_nil(Repo.reload(graph.workflow).deleted_at)} == {0, true}
    end
  end

  defp body_of(dataclip_id),
    do:
      Repo.one(
        from(d in Lightning.Invocation.Dataclip,
          where: d.id == ^dataclip_id,
          select: d.body
        )
      )

  defp entry(key, code, detail),
    do: %{"pointer" => "#/#{key}", "code" => code, "detail" => detail}
end
