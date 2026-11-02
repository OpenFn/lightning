defmodule LightningWeb.API.ProjectMembers.WhoMayReachItTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.ApiProjectMembersHelpers
  import LightningWeb.ApiProjectsHelpers
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  # A body none of the routes accept, so a refusal that comes first is visible.
  @body ~s({"nonsense": 1})

  setup %{conn: conn} do
    [owner, admin, editor, viewer, short_of_mfa, stranger] =
      insert_list(6, :user)

    support = insert(:user, support_user: true)
    superuser = insert(:user, role: :superuser)

    project =
      insert(:project,
        allow_support_access: true,
        project_users: [
          %{user: owner, role: :owner},
          %{user: admin, role: :admin},
          %{user: editor, role: :editor},
          %{user: viewer, role: :viewer}
        ]
      )

    mfa_project =
      insert(:project,
        requires_mfa: true,
        project_users: [
          %{user: short_of_mfa, role: :owner},
          %{user: viewer, role: :viewer}
        ]
      )

    %{
      conn: put_req_header(conn, "accept", "application/json"),
      users: %{
        owner: owner,
        admin: admin,
        editor: editor,
        viewer: viewer,
        short_of_mfa: short_of_mfa,
        stranger: stranger,
        support: support,
        superuser: superuser
      },
      project: project,
      mfa_project: mfa_project
    }
  end

  describe "who may reach it" do
    test "a caller refused the project gets the same 403 for it, an id that names no project and one that isn't a UUID, on every member route",
         %{conn: conn, users: users, project: project, mfa_project: mfa_project} do
      target = users.viewer.id
      unknown = Ecto.UUID.generate()
      three = &[&1, unknown, "not-a-uuid"]

      everywhere = [
        {users.stranger, three.(project.id)},
        {users.short_of_mfa, three.(mfa_project.id)},
        {users.superuser, [project.id]}
      ]

      refused = %{
        list: everywhere,
        add:
          everywhere ++
            for(
              u <- [:editor, :viewer, :support],
              do: {users[u], three.(project.id)}
            ),
        remove:
          everywhere ++
            for(
              u <- [:editor, :viewer, :support],
              do: {users[u], three.(project.id)}
            ),
        notifications: everywhere ++ [{users.support, three.(project.id)}]
      }

      for {route, callers} <- refused, {user, ids} <- callers, id <- ids do
        conn
        |> with_pat(user)
        |> reach(route, id, target)
        |> assert_problem(403, :forbidden, [])
      end

      assert role_of(project.id, target) == :viewer
      assert role_of(mfa_project.id, target) == :viewer
    end

    test "a member a route admits gets 400 for a user id that isn't a UUID, and 404 for one that names nobody it can act on",
         %{conn: conn, users: users, project: project} do
      for {route, user} <- [
            add: users.admin,
            remove: users.admin,
            notifications: users.viewer
          ] do
        conn
        |> with_pat(user)
        |> reach(route, project.id, "not-a-uuid")
        |> assert_problem(400, :invalid_parameter, [
          not_a_uuid_entry(%{"path" => "user_id"})
        ])
      end

      for route <- [:add, :remove] do
        conn
        |> with_pat(users.admin)
        |> reach(route, project.id, Ecto.UUID.generate())
        |> assert_problem(404, :not_found, [])
      end
    end

    test "the service account reaches the member routes but not anyone's notifications",
         %{conn: conn, users: users, project: project} do
      {conn, _account} = with_service_account(conn, ["projects:write"])

      assert conn |> reach(:list, project.id, nil) |> json_response(200)

      for route <- [:add, :remove] do
        conn
        |> reach(route, project.id, Ecto.UUID.generate())
        |> assert_problem(404, :not_found, [])
      end

      for project_id <- [project.id, Ecto.UUID.generate(), "not-a-uuid"] do
        conn
        |> reach(:notifications, project_id, users.viewer.id)
        |> assert_problem(403, :forbidden, [])
      end
    end

    test "a superuser or the service account gets 400 for a project id that isn't a UUID, and 404 for one that names no project",
         %{conn: conn, users: users} do
      {service_account_conn, _account} =
        with_service_account(conn, ["projects:write"])

      callers = [
        {with_pat(conn, users.superuser),
         [:list, :add, :remove, :notifications]},
        {service_account_conn, [:list, :add, :remove]}
      ]

      for {caller, routes} <- callers, route <- routes do
        caller
        |> reach(route, Ecto.UUID.generate(), users.viewer.id)
        |> assert_problem(404, :not_found, [])

        caller
        |> reach(route, "not-a-uuid", users.viewer.id)
        |> assert_problem(400, :invalid_parameter, [
          not_a_uuid_entry(%{"path" => "project_id"})
        ])
      end
    end

    test "a project scheduled for deletion is 403 to a stranger and 409 to its members, on every member route",
         %{conn: conn, users: users} do
      project = scheduled_project([%{user: users.owner, role: :owner}])

      for route <- [:list, :add, :remove, :notifications],
          {user, status, code} <- [
            {users.stranger, 403, :forbidden},
            {users.owner, 409, :scheduled_for_deletion}
          ] do
        conn
        |> with_pat(user)
        |> reach(route, project.id, users.owner.id)
        |> assert_problem(status, code, [])
      end
    end
  end

  defp reach(conn, :list, project_id, _user_id),
    do: get(conn, "/api/projects/#{project_id}/members")

  defp reach(conn, :add, project_id, user_id),
    do:
      send_json(
        conn,
        :put,
        "/api/projects/#{project_id}/members/#{user_id}",
        @body
      )

  defp reach(conn, :remove, project_id, user_id),
    do: delete(conn, "/api/projects/#{project_id}/members/#{user_id}")

  defp reach(conn, :notifications, project_id, user_id),
    do:
      send_json(
        conn,
        :put,
        "/api/projects/#{project_id}/members/#{user_id}/notifications",
        @body
      )
end
