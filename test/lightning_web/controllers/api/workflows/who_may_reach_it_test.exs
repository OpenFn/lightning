defmodule LightningWeb.API.Workflows.WhoMayReachItTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  alias Lightning.Workflows.Presence
  alias Lightning.Workflows.Workflow

  setup %{conn: conn} do
    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")

    [editor, viewer, short_of_mfa, stranger] = insert_list(4, :user)

    project =
      insert(:project,
        project_users: [
          %{user: editor, role: :editor},
          %{user: viewer, role: :viewer}
        ]
      )

    mfa_project =
      insert(:project,
        requires_mfa: true,
        project_users: [%{user: short_of_mfa, role: :editor}]
      )

    {service_account, _account} = with_service_account(conn, ["projects:write"])

    %{
      conn: conn,
      project: project,
      mfa_project: mfa_project,
      own: insert(:simple_workflow, name: "before", project: project),
      mfa_own: insert(:simple_workflow, name: "before", project: mfa_project),
      elsewhere: insert(:simple_workflow, name: "before"),
      deleted:
        insert(:simple_workflow,
          project: project,
          deleted_at: DateTime.utc_now()
        ),
      editor: assign_bearer(conn, editor),
      viewer: assign_bearer(conn, viewer),
      short_of_mfa: assign_bearer(conn, short_of_mfa),
      stranger: assign_bearer(conn, stranger),
      superuser: assign_bearer(conn, insert(:user, role: :superuser)),
      service_account: service_account
    }
  end

  describe "who may reach it" do
    test "creating: a refused caller gets 403 for every project id, a superuser or the service account 404 for an unknown one and 400 for a malformed one, and nothing is inserted",
         context do
      %{project: project, mfa_project: mfa_project} = context
      unknown = Ecto.UUID.generate()
      refused = {403, :forbidden, []}

      rows =
        for(
          pid <- [project.id, unknown, "not-a-uuid"],
          do: {context.stranger, pid, refused}
        ) ++
          [
            {context.viewer, project.id, refused},
            {context.short_of_mfa, mfa_project.id, refused},
            {context.superuser, project.id, refused}
          ] ++
          for(
            caller <- [context.superuser, context.service_account],
            row <- [
              {unknown, {404, :not_found, []}},
              {"not-a-uuid",
               {400, :invalid_parameter,
                [not_a_uuid_entry(%{"path" => "project_id"})]}}
            ],
            do: Tuple.insert_at(row, 0, caller)
          )

      for {caller, pid, {status, code, entries}} <- rows do
        caller
        |> post(
          ~p"/api/projects/#{pid}/workflows",
          Jason.encode!(
            build(:simple_workflow, name: "renamed", project_id: pid)
          )
        )
        |> assert_problem(status, code, entries)
      end

      refute Repo.get_by(Workflow, name: "renamed")
    end

    test "updating: a refused caller gets 403 for every id, even while the workflow is open in the editor, a permitted one 404 for a workflow the project hasn't got and 400 for a malformed id, and nothing changes",
         context do
      %{project: project, mfa_project: mfa_project, own: own} = context
      unknown = Ecto.UUID.generate()
      refused = {403, :forbidden, []}
      not_found = {404, :not_found, []}

      Presence.track_user_presence(insert(:user), own, self())

      rows =
        for(
          caller <- [context.viewer, context.superuser],
          id <- [own.id, unknown, "not-a-uuid"],
          do: {caller, project.id, id, refused}
        ) ++
          for(
            id <- [own.id, unknown, "not-a-uuid", context.elsewhere.id],
            do: {context.stranger, project.id, id, refused}
          ) ++
          for(
            id <- [context.mfa_own.id, unknown, "not-a-uuid"],
            do: {context.short_of_mfa, mfa_project.id, id, refused}
          ) ++
          [
            {context.superuser, unknown, unknown, not_found},
            {context.superuser, "not-a-uuid", unknown,
             {400, :invalid_parameter,
              [not_a_uuid_entry(%{"path" => "project_id"})]}}
          ] ++
          for(
            caller <- [context.editor, context.service_account],
            {id, expected} <- [
              {"not-a-uuid",
               {400, :invalid_parameter, [not_a_uuid_entry(%{"path" => "id"})]}},
              {unknown, not_found},
              {context.elsewhere.id, not_found},
              {context.deleted.id, not_found}
            ],
            do: {caller, project.id, id, expected}
          )

      for {caller, pid, id, {status, code, entries}} <- rows,
          verb <- [:patch, :put] do
        caller
        |> update(verb, pid, id)
        |> assert_problem(status, code, entries)
      end

      for workflow <- [own, context.mfa_own, context.elsewhere, context.deleted] do
        assert Repo.reload!(workflow).name == workflow.name
      end

      refute Repo.get_by(Workflow, name: "renamed")
    end

    test "admin, editor and owner can create a workflow", %{conn: conn} do
      for role <- [:admin, :editor, :owner] do
        user = insert(:user)
        project = insert(:project, project_users: [%{user: user, role: role}])

        workflow =
          build(:simple_workflow,
            name: "#{role}-created-workflow",
            project_id: project.id
          )

        resp_conn =
          conn
          |> assign_bearer(user)
          |> post(
            ~p"/api/projects/#{project.id}/workflows/",
            Jason.encode!(workflow)
          )

        assert %{"workflow" => %{"id" => id}} =
                 json_response(resp_conn, 201),
               "expected #{role} to be allowed to create a workflow"

        assert Repo.get(Workflow, id)
      end
    end

    test "admin, editor and owner can update a workflow", %{conn: conn} do
      for role <- [:admin, :editor, :owner] do
        user = insert(:user)
        project = insert(:project, project_users: [%{user: user, role: role}])

        workflow =
          insert(:simple_workflow, name: "#{role}-original", project: project)
          |> Repo.reload()

        resp_conn =
          conn
          |> assign_bearer(user)
          |> patch(
            ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
            Jason.encode!(%{name: "#{role}-updated"})
          )

        assert %{"workflow" => %{}} =
                 json_response(resp_conn, 200),
               "expected #{role} to be allowed to update a workflow"

        assert Repo.reload(workflow).name == "#{role}-updated"
      end
    end
  end

  defp update(conn, :patch, pid, id) do
    patch(
      conn,
      ~p"/api/projects/#{pid}/workflows/#{id}",
      Jason.encode!(%{name: "renamed"})
    )
  end

  # A whole document naming the path's id, which a PUT that created would take.
  defp update(conn, :put, pid, id) do
    put(
      conn,
      ~p"/api/projects/#{pid}/workflows/#{id}",
      Jason.encode!(
        build(:simple_workflow, id: id, name: "renamed", project_id: pid)
      )
    )
  end
end
