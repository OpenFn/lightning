defmodule LightningWeb.API.WorkOrders.WhoMayReachItTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.HistoryHelpers
  import LightningWeb.API.ProblemHelpers

  alias Lightning.Repo
  alias Lightning.WorkOrder

  setup %{conn: conn} do
    context = history_callers(conn)
    graph = runnable_workflow(context.project)
    mfa_graph = runnable_workflow(context.mfa_project)

    Map.merge(context, %{
      graph: graph,
      mfa_graph: mfa_graph,
      own: pending_work_order(graph),
      mfa_own: pending_work_order(mfa_graph)
    })
  end

  @refused {403, :forbidden, []}
  @not_found {404, :not_found, []}

  describe "who may reach it" do
    test "starting: a refused caller gets 403 for every project and workflow id, a permitted one 404 for a workflow the project hasn't got and 400 for a malformed id, and nothing starts",
         context do
      %{project: project, mfa_project: mfa_project, graph: graph} = context
      unknown = Ecto.UUID.generate()
      own = graph.workflow.id
      elsewhere = runnable_workflow(insert(:project)).workflow.id

      deleted =
        runnable_workflow(project, deleted_at: DateTime.utc_now()).workflow.id

      bad_workflow_id =
        {400, :invalid_parameter, [not_a_uuid_entry(%{"path" => "workflow_id"})]}

      bad_project_id =
        {400, :invalid_parameter, [not_a_uuid_entry(%{"path" => "project_id"})]}

      rows =
        for(
          caller <- [:stranger, :superuser, :service_account],
          pid <- [project.id, unknown, "not-a-uuid"],
          wid <- [own, unknown, "not-a-uuid"],
          not (caller == :superuser and pid != project.id),
          do: {caller, pid, wid, @refused}
        ) ++
          for(
            wid <- [own, unknown, "not-a-uuid"],
            do: {:viewer, project.id, wid, @refused}
          ) ++
          for(
            wid <- [context.mfa_graph.workflow.id, unknown, "not-a-uuid"],
            do: {:short_of_mfa, mfa_project.id, wid, @refused}
          ) ++
          [
            {:superuser, unknown, own, @not_found},
            {:superuser, "not-a-uuid", own, bad_project_id},
            {:editor, unknown, own, @refused},
            {:editor, project.id, unknown, @not_found},
            {:editor, project.id, elsewhere, @not_found},
            {:editor, project.id, deleted, @not_found},
            {:editor, project.id, "not-a-uuid", bad_workflow_id}
          ]

      for {caller, pid, wid, {status, code, entries}} <- rows do
        context
        |> Map.fetch!(caller)
        |> post(
          "/api/projects/#{pid}/workflows/#{wid}/work_orders",
          Jason.encode!(%{job_id: graph.job_a.id})
        )
        |> assert_problem(status, code, entries)
      end

      assert Repo.aggregate(WorkOrder, :count) == 2
    end

    test "retrying and cancelling many: a refused caller gets 403 for every project id, and nothing changes",
         context do
      %{project: project, mfa_project: mfa_project, own: own} = context
      unknown = Ecto.UUID.generate()

      bad_project_id =
        {400, :invalid_parameter, [not_a_uuid_entry(%{"path" => "project_id"})]}

      rows =
        for(
          caller <- [:stranger, :service_account],
          pid <- [project.id, unknown, "not-a-uuid"],
          do: {caller, pid, @refused}
        ) ++
          [
            {:viewer, project.id, @refused},
            {:short_of_mfa, mfa_project.id, @refused},
            {:superuser, project.id, @refused},
            {:superuser, unknown, @not_found},
            {:superuser, "not-a-uuid", bad_project_id},
            {:editor, unknown, @refused},
            {:editor, "not-a-uuid", @refused}
          ]

      for {caller, pid, {status, code, entries}} <- rows,
          action <- ["retries", "cancellations"] do
        context
        |> Map.fetch!(caller)
        |> post(
          "/api/projects/#{pid}/work_orders/#{action}",
          Jason.encode!(%{work_order_ids: [own.id]})
        )
        |> assert_problem(status, code, entries)
      end

      assert Repo.reload!(hd(own.runs)).state == :available
    end

    test "cancelling one: everyone but a permitted person gets the same 403 for every id, and so does a permitted one for an unknown or malformed id",
         context do
      unknown = Ecto.UUID.generate()

      rows =
        for(
          caller <- [:stranger, :superuser, :service_account, :viewer],
          id <- [context.own.id, unknown, "not-a-uuid"],
          do: {caller, id}
        ) ++
          for(
            id <- [context.mfa_own.id, unknown, "not-a-uuid"],
            do: {:short_of_mfa, id}
          ) ++
          for(id <- [unknown, "not-a-uuid"], do: {:editor, id})

      for {caller, id} <- rows do
        context
        |> Map.fetch!(caller)
        |> patch("/api/work_orders/#{id}", Jason.encode!(%{state: "cancelled"}))
        |> assert_problem(403, :forbidden, [])
      end

      assert Repo.reload!(hd(context.own.runs)).state == :available
    end

    test "every route in a project scheduled for deletion is 409 scheduled_for_deletion to a permitted person",
         %{editor: editor, project: project, own: own, graph: graph} do
      Repo.update!(
        Ecto.Changeset.change(project,
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
        )
      )

      for {verb, path, body} <- [
            {:post,
             "/api/projects/#{project.id}/workflows/#{graph.workflow.id}/work_orders",
             %{job_id: graph.job_a.id}},
            {:post, "/api/projects/#{project.id}/work_orders/retries",
             %{work_order_ids: [own.id]}},
            {:post, "/api/projects/#{project.id}/work_orders/cancellations",
             %{work_order_ids: [own.id]}},
            {:patch, "/api/work_orders/#{own.id}", %{state: "cancelled"}}
          ] do
        editor
        |> dispatch(@endpoint, verb, path, Jason.encode!(body))
        |> assert_problem(409, :scheduled_for_deletion, [])
      end

      assert Repo.reload!(hd(own.runs)).state == :available
    end
  end
end
