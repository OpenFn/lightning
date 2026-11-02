defmodule LightningWeb.API.HistoryExports.WhoMayReachItTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.HistoryHelpers
  import LightningWeb.API.ProblemHelpers

  alias Lightning.Projects.File, as: ProjectFile
  alias Lightning.Repo

  setup %{conn: conn} do
    context = history_callers(conn)

    Map.merge(context, %{
      own: insert(:project_file, project: context.project),
      mfa_own: insert(:project_file, project: context.mfa_project),
      elsewhere: insert(:project_file)
    })
  end

  @refused {403, :forbidden, []}
  @not_found {404, :not_found, []}

  describe "who may reach it" do
    test "asking for an export: a refused caller gets 403 for every project id, and nothing is exported",
         context do
      %{project: project, mfa_project: mfa_project} = context
      unknown = Ecto.UUID.generate()

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
            {:superuser, "not-a-uuid", bad_id("project_id")},
            {:editor, unknown, @refused}
          ]

      for {caller, pid, {status, code, entries}} <- rows do
        context
        |> Map.fetch!(caller)
        |> post("/api/projects/#{pid}/history_exports", Jason.encode!(%{}))
        |> assert_problem(status, code, entries)
      end

      assert Repo.aggregate(ProjectFile, :count) == 3
    end

    test "listing, reading and downloading: a refused caller gets 403 for every id, a member 404 for an export the project hasn't got and 400 for a malformed id",
         context do
      %{project: project, mfa_project: mfa_project, own: own} = context
      unknown = Ecto.UUID.generate()
      base = &"/api/projects/#{&1}/history_exports"

      one = fn pid, id ->
        [base.(pid) <> "/#{id}", base.(pid) <> "/#{id}/download"]
      end

      rows =
        for(
          caller <- [:stranger, :service_account, :superuser],
          path <-
            [base.(project.id)] ++
              one.(project.id, own.id) ++
              one.(project.id, unknown) ++ one.(project.id, "not-a-uuid"),
          do: {caller, path, @refused}
        ) ++
          for(
            path <-
              [base.(mfa_project.id)] ++
                one.(mfa_project.id, context.mfa_own.id) ++
                one.(mfa_project.id, unknown) ++
                one.(mfa_project.id, "not-a-uuid"),
            do: {:short_of_mfa, path, @refused}
          ) ++
          for(
            caller <- [:viewer, :editor],
            {ids, expected} <- [
              {[unknown, context.elsewhere.id], @not_found},
              {["not-a-uuid"], bad_id("id")}
            ],
            id <- ids,
            path <- one.(project.id, id),
            do: {caller, path, expected}
          ) ++
          for(
            path <- [base.(unknown) | one.(unknown, own.id)],
            do: {:viewer, path, @refused}
          )

      for {caller, path, {status, code, entries}} <- rows do
        context
        |> Map.fetch!(caller)
        |> get(path)
        |> assert_problem(status, code, entries)
      end
    end

    test "every route in a project scheduled for deletion is 409 scheduled_for_deletion to a permitted person",
         %{editor: editor, project: project, own: own} do
      Repo.update!(
        Ecto.Changeset.change(project,
          scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
        )
      )

      base = "/api/projects/#{project.id}/history_exports"

      for {verb, path} <- [
            {:post, base},
            {:get, base},
            {:get, "#{base}/#{own.id}"},
            {:get, "#{base}/#{own.id}/download"}
          ] do
        editor
        |> dispatch(@endpoint, verb, path, Jason.encode!(%{}))
        |> assert_problem(409, :scheduled_for_deletion, [])
      end
    end
  end

  defp bad_id(segment),
    do: {400, :invalid_parameter, [not_a_uuid_entry(%{"path" => segment})]}
end
