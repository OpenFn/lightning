defmodule LightningWeb.API.WorkflowHistory.WhoMayReachItTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import Lightning.Factories

  describe "who may reach it" do
    test "a workflow's snapshots and versions: only a member learns which exist, and only of their project's workflows; anyone else gets 403 for every id",
         %{conn: conn} do
      conn = put_req_header(conn, "accept", "application/json")
      [viewer, short_of_mfa, stranger] = insert_list(3, :user)
      superuser = insert(:user, role: :superuser)

      project =
        insert(:project, project_users: [%{user: viewer, role: :viewer}])

      mfa_project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: short_of_mfa, role: :editor}]
        )

      own = insert(:simple_workflow, project: project)
      own_snapshot = insert(:snapshot, workflow: own)
      mfa_own = insert(:simple_workflow, project: mfa_project)
      elsewhere = insert(:simple_workflow)
      elsewhere_snapshot = insert(:snapshot, workflow: elsewhere)

      deleted =
        insert(:simple_workflow,
          project: project,
          deleted_at: DateTime.utc_now()
        )

      unknown = Ecto.UUID.generate()
      refused = {403, :forbidden, []}
      not_found = {404, :not_found, []}

      # Each workflow id goes to all three routes, with a snapshot id that
      # exists for the route reading one.
      workflow_rows =
        for(
          caller <- [stranger, superuser],
          id <- [own.id, unknown, "not-a-uuid", elsewhere.id],
          do: {caller, id, refused}
        ) ++
          for(
            id <- [mfa_own.id, unknown, "not-a-uuid"],
            do: {short_of_mfa, id, refused}
          ) ++
          [
            {viewer, unknown, refused},
            {viewer, "not-a-uuid", refused},
            {viewer, elsewhere.id, refused},
            {viewer, deleted.id, not_found}
          ]

      for {caller, id, {status, code, entries}} <- workflow_rows,
          path <- [
            ~p"/api/workflows/#{id}/snapshots",
            ~p"/api/workflows/#{id}/snapshots/#{own_snapshot.id}",
            ~p"/api/workflows/#{id}/versions"
          ] do
        conn
        |> assign_bearer(caller)
        |> get(path)
        |> assert_problem(status, code, entries)
      end

      for {snapshot_id, {status, code, entries}} <- [
            {"not-a-uuid",
             {400, :invalid_parameter,
              [not_a_uuid_entry(%{"path" => "snapshot_id"})]}},
            {unknown, not_found},
            {elsewhere_snapshot.id, not_found}
          ] do
        conn
        |> assign_bearer(viewer)
        |> get(~p"/api/workflows/#{own.id}/snapshots/#{snapshot_id}")
        |> assert_problem(status, code, entries)
      end
    end
  end
end
