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
    test "a caller refused on a project gets the same 403 for it, an id that names no project and one that isn't a UUID, and nothing is written",
         %{conn: conn} do
      [editor, viewer, other_owner, short_of_mfa, stranger] =
        insert_list(5, :user)

      support = insert(:user, support_user: true)
      superuser = insert(:user, role: :superuser)

      project =
        insert(:project,
          name: "before",
          project_users: [
            %{user: editor, role: :editor},
            %{user: viewer, role: :viewer}
          ]
        )

      insert(:project, project_users: [%{user: other_owner, role: :owner}])

      mfa_project =
        insert(:project,
          name: "before",
          requires_mfa: true,
          project_users: [%{user: short_of_mfa, role: :admin}]
        )

      supported = insert(:project, name: "before", allow_support_access: true)
      unknown = Ecto.UUID.generate()
      three_ids = &[&1, unknown, "not-a-uuid"]

      refused =
        for(
          user <- [editor, viewer],
          id <- three_ids.(project.id),
          do: {user, :put, id}
        ) ++
          [{other_owner, :put, unknown}, {support, :put, supported.id}] ++
          for(
            verb <- [:get, :put],
            {user, ids} <- [
              {short_of_mfa, three_ids.(mfa_project.id)},
              {stranger, three_ids.(project.id)},
              {superuser, [project.id]}
            ],
            id <- ids,
            do: {user, verb, id}
          )

      for {user, verb, id} <- refused do
        conn
        |> with_pat(user)
        |> reach(verb, id)
        |> assert_problem(403, :forbidden, [])
      end

      for written <- [project, mfa_project, supported] do
        assert Lightning.Repo.reload!(written).name == "before"
      end

      refute Lightning.Repo.get(Lightning.Projects.Project, unknown)
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

    test "a superuser or the service account gets 400 for an id that isn't a UUID, and reads one that names no project as 404",
         %{conn: conn} do
      {service_account_conn, _account} =
        with_service_account(conn, ["projects:write"])

      superuser_conn = with_pat(conn, insert(:user, role: :superuser))

      for caller <- [superuser_conn, service_account_conn] do
        caller
        |> reach(:get, Ecto.UUID.generate())
        |> assert_problem(404, :not_found, [])

        for verb <- [:get, :put] do
          caller
          |> reach(verb, "not-a-uuid")
          |> assert_problem(400, :invalid_parameter, [
            not_a_uuid_entry(%{"path" => "id"})
          ])
        end
      end

      refute Lightning.Repo.get_by(Lightning.Projects.Project, name: "renamed")
    end

    test "a project scheduled for deletion is 403 to a stranger and 409 to a member or a service account, on both routes",
         %{conn: conn} do
      {service_account_conn, _account} =
        with_service_account(conn, ["projects:write"])

      owner = insert(:user)
      stranger = insert(:user)

      callers = [
        {with_pat(conn, stranger), 403, :forbidden},
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
