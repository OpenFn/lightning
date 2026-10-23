defmodule LightningWeb.API.Projects.WhoMayReachItTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.ApiProjectsHelpers
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "who may reach it" do
    test "an editor or a viewer may not replace a project, and a stranger may not see or replace it",
         %{conn: conn} do
      refusals = [
        {:editor, [:put], 403, :forbidden},
        {:viewer, [:put], 403, :forbidden},
        {:stranger, [:get, :put], 404, :not_found}
      ]

      for {role, verbs, status, code} <- refusals, verb <- verbs do
        user = insert(:user)
        members = if role == :stranger, do: [], else: [%{user: user, role: role}]
        project = insert(:project, name: "before", project_users: members)

        conn
        |> with_pat(user)
        |> reach(verb, project.id)
        |> assert_problem(status, code, [])

        assert Lightning.Repo.reload!(project).name == "before",
               "#{role} changed the project by #{verb}"
      end
    end

    test "an owner or an admin may replace a project", %{conn: conn} do
      for role <- [:owner, :admin] do
        user = insert(:user)
        project = insert(:project, project_users: [%{user: user, role: role}])

        conn
        |> with_pat(user)
        |> put_project(project.id, %{"name" => "after"})
        |> json_response(200)

        assert Lightning.Repo.reload!(project).name == "after"
      end
    end

    test "an id that names no project is 404 to read, and creating it is refused unless the token's user is a superuser",
         %{conn: conn} do
      conn = with_pat(conn, insert(:user))
      id = Ecto.UUID.generate()

      conn |> reach(:get, id) |> assert_problem(404, :not_found, [])
      conn |> reach(:put, id) |> assert_problem(403, :forbidden, [])

      refute Lightning.Repo.get(Lightning.Projects.Project, id)
    end

    test "a project scheduled for deletion is 404 to a stranger and 409 to a member or a service account, on both routes",
         %{conn: conn} do
      {service_account_conn, _account} =
        with_service_account(conn, ["projects:write"])

      owner = insert(:user)
      stranger = insert(:user)

      callers = [
        {with_pat(conn, stranger), 404, :not_found},
        {with_pat(conn, owner), 409, :scheduled_for_deletion},
        {service_account_conn, 409, :scheduled_for_deletion}
      ]

      for {caller, status, code} <- callers, verb <- [:get, :put] do
        project = scheduled_project([%{user: owner, role: :owner}])

        caller
        |> reach(verb, project.id)
        |> assert_problem(status, code, [])

        assert Lightning.Repo.reload!(project).name == project.name
      end
    end
  end

  # A body no route would accept, so a refusal that comes first is visible.
  defp reach(conn, :get, id), do: get(conn, ~p"/api/projects/#{id}")

  defp reach(conn, :put, id),
    do: put_project(conn, id, %{"name" => "renamed", "nonsense" => 1})
end
