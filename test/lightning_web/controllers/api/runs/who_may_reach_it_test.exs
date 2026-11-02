defmodule LightningWeb.API.Runs.WhoMayReachItTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.HistoryHelpers
  import LightningWeb.API.ProblemHelpers

  alias Lightning.Repo

  setup %{conn: conn} do
    context = history_callers(conn)
    graph = runnable_workflow(context.project)
    mfa_graph = runnable_workflow(context.mfa_project)

    Map.merge(context, %{
      own: hd(pending_work_order(graph).runs),
      mfa_own: hd(pending_work_order(mfa_graph).runs),
      step_id: ran_work_order(graph).step_a.id
    })
  end

  describe "who may reach it" do
    test "cancelling, retrying and reading steps: everyone but a permitted person gets the same 403 for every id, and so does a permitted one for an unknown or malformed id",
         context do
      unknown = Ecto.UUID.generate()

      writes = [
        {:patch, &"/api/runs/#{&1}", %{state: "cancelled"}},
        {:post, &"/api/runs/#{&1}/retries", %{step_id: context.step_id}}
      ]

      read = {:get, &"/api/runs/#{&1}/steps", nil}

      rows =
        for(
          caller <- [:stranger, :superuser, :service_account],
          route <- [read | writes],
          id <- [context.own.id, unknown, "not-a-uuid"],
          do: {caller, route, id}
        ) ++
          for(
            route <- writes,
            id <- [context.own.id, unknown, "not-a-uuid"],
            do: {:viewer, route, id}
          ) ++
          for(
            route <- [read | writes],
            id <- [context.mfa_own.id, unknown, "not-a-uuid"],
            do: {:short_of_mfa, route, id}
          ) ++
          for(
            caller <- [:editor, :viewer],
            route <- [read | writes],
            id <- [unknown, "not-a-uuid"],
            do: {caller, route, id}
          )

      for {caller, {verb, path, body}, id} <- rows do
        context
        |> Map.fetch!(caller)
        |> dispatch(@endpoint, verb, path.(id), body && Jason.encode!(body))
        |> assert_problem(403, :forbidden, [])
      end

      assert Repo.reload!(context.own).state == :available
    end

    test "a run in a project scheduled for deletion is 409 scheduled_for_deletion to a permitted person",
         %{editor: editor, project: project, own: own} do
      Repo.update!(
        Ecto.Changeset.change(project,
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
        )
      )

      for {verb, path, body} <- [
            {:patch, "/api/runs/#{own.id}", %{state: "cancelled"}},
            {:post, "/api/runs/#{own.id}/retries", %{}},
            {:get, "/api/runs/#{own.id}/steps", nil}
          ] do
        editor
        |> dispatch(@endpoint, verb, path, body && Jason.encode!(body))
        |> assert_problem(409, :scheduled_for_deletion, [])
      end

      assert Repo.reload!(own).state == :available
    end
  end
end
