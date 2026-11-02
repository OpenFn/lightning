defmodule LightningWeb.API.Runs.RetryingTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.HistoryHelpers
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers

  alias Lightning.RaceHelpers
  alias Lightning.Repo
  alias Lightning.Run

  setup %{conn: conn} do
    context = history_callers(conn)
    graph = runnable_workflow(context.project)

    Map.merge(context, Map.put(ran_work_order(graph), :graph, graph))
  end

  describe "retrying" do
    test "a session token retries a run from a step, and gets the new run on the same work order",
         %{run: run, step_b: step_b, editor_user: editor, work_order: wo} do
      conn =
        build_conn()
        |> session_conn(editor)
        |> post(~p"/api/runs/#{run.id}/retries", %{step_id: step_b.id})

      assert %{"data" => %{"id" => id}} = body = json_response(conn, 201)
      url = "#{LightningWeb.Endpoint.url()}/api/runs/#{id}"

      assert body == %{
               "data" => %{
                 "type" => "runs",
                 "id" => id,
                 "relationships" => %{},
                 "links" => %{"self" => url},
                 "attributes" => %{
                   "state" => "available",
                   "started_at" => nil,
                   "finished_at" => nil,
                   "priority" => "immediate",
                   "error_type" => nil
                 }
               },
               "included" => [],
               "links" => %{"self" => url}
             }

      new_run = Repo.get!(Run, id) |> Repo.preload(:steps)

      assert %{
               work_order_id: work_order_id,
               starting_job_id: starting_job_id,
               created_by_id: created_by_id
             } = new_run

      assert {work_order_id, starting_job_id, created_by_id} ==
               {wo.id, step_b.job_id, editor.id}

      # The step that doesn't depend on b is carried over, not run again.
      assert Enum.map(new_run.steps, & &1.job_id) == [run_step_a_job(run)]
    end

    test "a personal access token retries it too", %{
      editor: editor,
      run: run,
      step_a: step_a
    } do
      conn = post(editor, ~p"/api/runs/#{run.id}/retries", %{step_id: step_a.id})

      assert json_response(conn, 201)["data"]["attributes"]["state"] ==
               "available"
    end
  end

  describe "refusals" do
    test "a step_id that is missing, not a UUID or not this run's is 422, and nothing is retried",
         %{editor: editor, run: run} do
      other_step = insert(:step, input_dataclip: insert(:dataclip))

      for {body, entries} <- [
            {%{}, [entry("required", "can't be blank")]},
            {%{step_id: nil}, [entry("required", "can't be blank")]},
            {%{step_id: "not-a-uuid"}, [entry("type", "is not a UUID")]},
            {%{step_id: 7}, [entry("type", "is not a UUID")]},
            {%{step_id: other_step.id},
             [entry("not_found", "is not a step of this run")]},
            {%{step_id: Ecto.UUID.generate(), from: "start"},
             [
               entry("not_found", "is not a step of this run"),
               %{
                 "pointer" => "#/from",
                 "code" => "unknown_key",
                 "detail" => "is not accepted"
               }
             ]}
          ] do
        editor
        |> post(~p"/api/runs/#{run.id}/retries", body)
        |> assert_problem(422, :invalid, entries)
      end

      assert runs_of(run) == 1
    end

    test "a body that isn't a JSON object is 400 malformed", %{
      editor: editor,
      run: run
    } do
      editor
      |> post(~p"/api/runs/#{run.id}/retries", Jason.encode!([1]))
      |> assert_problem(400, :malformed, [])
    end

    test "a step whose input has been wiped is 422 dataclip_wiped", %{
      editor: editor,
      graph: graph
    } do
      wiped = insert(:dataclip, wiped_at: DateTime.utc_now(), body: nil)
      %{run: run, step_a: step_a} = ran_work_order(graph, [], wiped)

      editor
      |> post(~p"/api/runs/#{run.id}/retries", %{step_id: step_a.id})
      |> assert_problem(422, :invalid, [
        entry("dataclip_wiped", "cannot retry run using a wiped dataclip")
      ])

      assert runs_of(run) == 1
    end

    test "a run whose workflow has been deleted is 409 scheduled_for_deletion, before the body is read",
         %{editor: editor, run: run, graph: graph} do
      Repo.update!(
        Ecto.Changeset.change(graph.workflow,
          deleted_at: DateTime.utc_now() |> DateTime.truncate(:second)
        )
      )

      editor
      |> post(~p"/api/runs/#{run.id}/retries", %{step_id: "not-a-uuid"})
      |> assert_problem(409, :scheduled_for_deletion, [])

      assert runs_of(run) == 1
    end

    test "the run limits are asked once the body is valid", %{
      editor: editor,
      run: run,
      step_a: step_a
    } do
      for {reason, status, code} <- run_limit_refusals() do
        limit_runs(reason)

        editor
        |> post(~p"/api/runs/#{run.id}/retries", %{step_id: step_a.id})
        |> assert_problem(status, code, [])

        editor
        |> post(~p"/api/runs/#{run.id}/retries", %{step_id: "not-a-uuid"})
        |> assert_problem(422, :invalid, [entry("type", "is not a UUID")])
      end

      assert runs_of(run) == 1
    end
  end

  describe "stale writes" do
    test "a workflow deleted after the run was read is 409 scheduled_for_deletion, and no run is made",
         %{editor: editor, run: run, step_a: step_a, graph: graph} do
      RaceHelpers.after_first_query("workflows", graph.workflow.id, fn id ->
        Repo.query!("UPDATE workflows SET deleted_at = now() WHERE id = $1", [
          id
        ])
      end)

      editor
      |> post(~p"/api/runs/#{run.id}/retries", %{step_id: step_a.id})
      |> assert_problem(409, :scheduled_for_deletion, [])

      assert runs_of(run) == 1
      refute is_nil(Repo.reload!(graph.workflow).deleted_at)
    end
  end

  defp entry(code, detail),
    do: %{"pointer" => "#/step_id", "code" => code, "detail" => detail}

  defp runs_of(run),
    do:
      Repo.aggregate(Ecto.assoc(Repo.reload!(run), [:work_order, :runs]), :count)

  defp run_step_a_job(run) do
    run
    |> Repo.preload(:steps)
    |> Map.fetch!(:steps)
    |> Enum.find(&(&1.exit_reason == "success"))
    |> Map.fetch!(:job_id)
  end
end
