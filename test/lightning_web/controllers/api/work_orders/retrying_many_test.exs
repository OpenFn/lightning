defmodule LightningWeb.API.WorkOrders.RetryingManyTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.HistoryHelpers
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers

  alias Lightning.Repo
  alias Lightning.Run

  setup %{conn: conn} do
    context = history_callers(conn)
    graph = runnable_workflow(context.project)
    %{work_order: first} = ran_work_order(graph)
    %{work_order: second} = ran_work_order(graph)

    wiped =
      insert(:dataclip,
        project: context.project,
        wiped_at: DateTime.utc_now(),
        body: nil
      )

    %{work_order: wiped_one} = ran_work_order(graph, [], wiped)

    Map.merge(context, %{
      graph: graph,
      first: first,
      second: second,
      wiped_one: wiped_one,
      path: ~p"/api/projects/#{context.project.id}/work_orders/retries"
    })
  end

  describe "retrying" do
    test "a session token retries every work order a filter matches, and hears how many were enqueued and discarded",
         %{path: path, editor_user: editor} = context do
      elsewhere = ran_work_order(runnable_workflow(insert(:project))).work_order

      conn =
        build_conn()
        |> session_conn(editor)
        |> post(path, %{filter: %{state: "failed"}})

      assert json_response(conn, 202) == %{"enqueued" => 2, "discarded" => 1}

      assert Enum.map(
               [context.first, context.second, context.wiped_one, elsewhere],
               &runs_of/1
             ) == [2, 2, 1, 1]
    end

    test "a personal access token retries listed work orders from a job", %{
      path: path,
      editor: editor,
      first: first,
      second: second,
      graph: graph
    } do
      conn =
        post(editor, path, %{work_order_ids: [first.id], job_id: graph.job_b.id})

      assert json_response(conn, 202) == %{"enqueued" => 1, "discarded" => 0}
      assert [runs_of(first), runs_of(second)] == [2, 1]

      assert Repo.get_by!(Run,
               work_order_id: first.id,
               starting_job_id: graph.job_b.id
             )
    end

    test "a work order of another project, or one the filter doesn't match, is neither enqueued nor discarded",
         %{path: path, editor: editor, first: first} do
      elsewhere = ran_work_order(runnable_workflow(insert(:project))).work_order

      for body <- [
            %{work_order_ids: [elsewhere.id]},
            %{filter: %{id: first.id, state: "success"}}
          ] do
        assert editor |> post(path, body) |> json_response(202) == %{
                 "enqueued" => 0,
                 "discarded" => 0
               }
      end

      assert [runs_of(first), runs_of(elsewhere)] == [1, 1]
    end
  end

  describe "refusals" do
    test "a body that selects nothing, both ways, or with bad filters or ids is 422 with every problem, and nothing is retried",
         %{path: path, editor: editor, first: first} do
      for {body, entries} <- [
            {%{},
             [entry("/filter", "required", "send filter or work_order_ids")]},
            {%{filter: %{}, work_order_ids: []},
             [entry("/work_order_ids", "exclusive", "can't be sent with filter")]},
            {%{filter: "failed"},
             [entry("/filter", "type", "must be an object")]},
            {%{
               filter: %{
                 state: "sideways",
                 inserted_after: "yesterday",
                 project_id: first.id
               },
               job: "a"
             },
             [
               entry("/filter/state", "not_allowed", "has an invalid entry"),
               entry("/filter/inserted_after", "type", "is invalid"),
               entry("/filter/project_id", "unknown_key", "is not accepted"),
               entry("/job", "unknown_key", "is not accepted")
             ]},
            {%{
               work_order_ids: Enum.map(1..101, fn _ -> Ecto.UUID.generate() end)
             },
             [
               entry(
                 "/work_order_ids",
                 "too_long",
                 "should have at most 100 item(s)"
               )
             ]},
            {%{work_order_ids: [first.id, "x", 3]},
             [
               entry("/work_order_ids/1", "type", "is not a UUID"),
               entry("/work_order_ids/2", "type", "is not a UUID")
             ]},
            {%{work_order_ids: first.id},
             [entry("/work_order_ids", "type", "must be a list")]},
            {%{work_order_ids: [first.id], job_id: "x"},
             [entry("/job_id", "type", "is not a UUID")]},
            {%{work_order_ids: [first.id], job_id: insert(:job).id},
             [entry("/job_id", "not_found", "names nothing you can see")]},
            {%{filter: %{state: "bogus"}, job_id: "nope"},
             [
               entry("/filter/state", "not_allowed", "has an invalid entry"),
               entry("/job_id", "type", "is not a UUID")
             ]},
            {%{work_order_ids: ["x"], job_id: insert(:job).id},
             [
               entry("/work_order_ids/0", "type", "is not a UUID"),
               entry("/job_id", "not_found", "names nothing you can see")
             ]}
          ] do
        editor
        |> post(path, body)
        |> assert_problem(422, :invalid, entries)
      end

      assert runs_of(first) == 1
    end

    test "a job outside the work orders' workflow is 422 mismatch", %{
      path: path,
      editor: editor,
      project: project,
      first: first
    } do
      other = runnable_workflow(project)

      editor
      |> post(path, %{work_order_ids: [first.id], job_id: other.job_a.id})
      |> assert_problem(422, :invalid, [
        entry(
          "/job_id",
          "mismatch",
          "is not in the workflow of every work order"
        )
      ])

      assert runs_of(first) == 1
    end

    test "a body that isn't a JSON object is 400 malformed", %{
      path: path,
      editor: editor
    } do
      editor
      |> post(path, Jason.encode!([]))
      |> assert_problem(400, :malformed, [])
    end

    test "the run limits are asked once the body is valid, with and without a job",
         %{path: path, editor: editor, first: first, graph: graph} do
      for {reason, status, code} <- run_limit_refusals(),
          job <- [%{}, %{job_id: graph.job_a.id}] do
        limit_runs(reason)

        editor
        |> post(path, Map.put(job, :work_order_ids, [first.id]))
        |> assert_problem(status, code, [])
      end

      assert runs_of(first) == 1
    end
  end

  defp entry(pointer, code, detail),
    do: %{"pointer" => "#" <> pointer, "code" => code, "detail" => detail}

  defp runs_of(work_order),
    do: Repo.aggregate(Ecto.assoc(work_order, :runs), :count)
end
