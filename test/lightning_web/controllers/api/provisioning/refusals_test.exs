defmodule LightningWeb.API.ProvisioningRefusalsTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProvisioningHelpers
  import LightningWeb.API.ProblemHelpers
  import Lightning.Factories

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "who may reach it, reading" do
    setup [:assign_bearer_for_api]

    test "every role reads the project and a non-member is told it doesn't exist",
         %{conn: conn, user: user} do
      for role <- [:owner, :admin, :editor, :viewer],
          path <- [:state, :yaml] do
        project =
          insert(:project, project_users: [%{user_id: user.id, role: role}])

        assert get(conn, read_path(path, project)).status == 200,
               "a #{role} was refused the #{path}"
      end

      project = insert(:project)

      for path <- [:state, :yaml] do
        conn
        |> get(read_path(path, project))
        |> assert_problem(404, :not_found, [])
      end
    end

    test "a repo connection token reads its own project and no other", %{
      conn: conn
    } do
      project = insert(:project)
      other_project = insert(:project)
      own = insert(:project_repo_connection, project: project)
      other = insert(:project_repo_connection, project: other_project)

      for path <- [:state, :yaml] do
        assert conn
               |> put_bearer(own.access_token)
               |> get(read_path(path, project))
               |> Map.fetch!(:status) == 200

        conn
        |> put_bearer(other.access_token)
        |> get(read_path(path, project))
        |> assert_problem(404, :not_found, [])
      end
    end
  end

  describe "who may reach it, importing" do
    setup [:assign_bearer_for_api]

    test "owners and admins import; editors and viewers are forbidden; a non-member is told the project doesn't exist",
         %{conn: conn, user: user} do
      for {member_role, refusal} <- [
            {:owner, nil},
            {:admin, nil},
            {:editor, {403, :forbidden}},
            {:viewer, {403, :forbidden}},
            {nil, {404, :not_found}}
          ] do
        project =
          insert(:project,
            project_users:
              if(member_role,
                do: [%{user_id: user.id, role: member_role}],
                else: []
              )
          )

        %{body: body} = valid_payload(project.id)
        response = post(conn, ~p"/api/provision", body)

        case refusal do
          nil ->
            assert response.status == 201, "a #{member_role} was refused"

          {status, code} ->
            assert_problem(response, status, code, [])

            assert Lightning.Repo.reload!(project).name == project.name,
                   "a refused #{member_role} still renamed the project"
        end
      end
    end

    test "a repo connection token imports into its own project and not another",
         %{conn: conn} do
      project = insert(:project)
      other_project = insert(:project)
      repo_connection = insert(:project_repo_connection, project: project)
      conn = put_bearer(conn, repo_connection.access_token)

      %{body: body} = valid_payload(project.id)
      assert post(conn, ~p"/api/provision", body).status == 201

      %{body: other_body} = valid_payload(other_project.id)

      conn
      |> post(~p"/api/provision", other_body)
      |> assert_problem(404, :not_found, [])
    end

    test "a user who isn't a superuser can't create a new project", %{
      conn: conn
    } do
      %{body: body} = valid_payload()

      conn
      |> post(~p"/api/provision", body)
      |> assert_problem(403, :forbidden, [])
    end
  end

  describe "a project scheduled for deletion" do
    setup [:assign_bearer_for_api]

    # Scheduling deletion removes no membership row and revokes no
    # repo-connection token, so both callers below still exist during the grace
    # window. They get the same 409 that the projects API gives.
    setup %{conn: conn, user: user} do
      project =
        insert(:project, project_users: [%{user_id: user.id, role: :owner}])

      workflow =
        insert(:simple_workflow, project: project)
        |> Lightning.Repo.preload([:jobs, :triggers, :edges])

      {:ok, project} = Lightning.Projects.schedule_project_deletion(project)

      [trigger] = workflow.triggers
      refute Lightning.Repo.reload!(trigger).enabled

      repo_connection = insert(:project_repo_connection, project: project)

      %{
        project: project,
        workflow: workflow,
        trigger: trigger,
        callers: [
          member: conn,
          repo_connection: put_bearer(build_conn(), repo_connection.access_token)
        ]
      }
    end

    # A refusal that still wrote would turn the triggers back on, which project
    # shutdown had disabled on purpose.
    test "a member and a repo connection token are refused on every route, and the trigger stays disabled",
         %{
           callers: callers,
           project: project,
           workflow: workflow,
           trigger: trigger
         } do
      requests = [
        fn conn -> get(conn, read_path(:state, project)) end,
        fn conn -> get(conn, read_path(:yaml, project)) end,
        fn conn ->
          post(
            conn,
            ~p"/api/provision",
            reenable_triggers_payload(project, workflow)
          )
        end
      ]

      for {caller, conn} <- callers, request <- requests do
        conn |> request.() |> assert_problem(409, :scheduled_for_deletion, [])

        assert Lightning.Repo.reload!(trigger).enabled == false,
               "the #{caller} re-enabled a trigger that project shutdown had disabled"
      end
    end

    test "a non-member is told nothing about the deletion", %{project: project} do
      %{conn: outsider} = assign_bearer_for_api(%{conn: build_conn()})

      for path <- [:state, :yaml] do
        outsider
        |> get(read_path(path, project))
        |> assert_problem(404, :not_found, [])
      end
    end
  end

  defp read_path(:state, project), do: ~p"/api/provision/#{project.id}"

  defp read_path(:yaml, project),
    do: ~p"/api/provision/yaml?#{%{id: project.id}}"
end
