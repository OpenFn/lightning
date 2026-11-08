defmodule LightningWeb.API.Organizations.WhoMayReachItTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.ApiOrganizationsHelpers
  import LightningWeb.ApiProjectMembersHelpers, only: [send_json: 4]
  import LightningWeb.ApiProjectsHelpers
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  # A body none of the routes accept, so a refusal that comes first is visible.
  @body ~s({"nonsense": 1})

  @reads [:show, :list_members]
  @manages [:rename, :add, :change_role, :remove]

  setup %{conn: conn} do
    [admin, member, stranger] = insert_list(3, :user)
    superuser = insert(:user, role: :superuser)
    organization = organization_with([{admin, :admin}, {member, :member}])

    %{
      conn: put_req_header(conn, "accept", "application/json"),
      users: %{
        admin: admin,
        member: member,
        stranger: stranger,
        superuser: superuser
      },
      organization: organization
    }
  end

  describe "who may reach it" do
    test "a caller refused the organization gets the same 403 for it, an id that names none and one that isn't a UUID",
         %{conn: conn, users: users, organization: organization} do
      ids = [organization.id, Ecto.UUID.generate(), "not-a-uuid"]

      refused =
        for(route <- @reads ++ @manages, do: {users.stranger, route}) ++
          for route <- @manages, do: {users.member, route}

      for {user, route} <- refused, id <- ids do
        conn
        |> with_pat(user)
        |> reach(route, id, users.member.id)
        |> assert_problem(403, :forbidden, [])
      end

      assert org_role_of(organization.id, users.member.id) == :member
    end

    test "a superuser or the service account gets 404 for an organization id that names none, and 400 for one that isn't a UUID",
         %{conn: conn, users: users} do
      {service_conn, _account} =
        with_service_account(conn, ["organizations:write"])

      for caller <- [with_pat(conn, users.superuser), service_conn],
          route <- @reads ++ @manages do
        caller
        |> reach(route, Ecto.UUID.generate(), users.member.id)
        |> assert_problem(404, :not_found, [])

        caller
        |> reach(route, "not-a-uuid", users.member.id)
        |> assert_problem(400, :invalid_parameter, [
          not_a_uuid_entry(%{"path" => path_of(route)})
        ])
      end
    end

    test "an admin gets 400 for a user id that isn't a UUID, and 404 for one that names no member",
         %{conn: conn, users: users, organization: organization} do
      for route <- [:change_role, :remove] do
        conn
        |> with_pat(users.admin)
        |> reach(route, organization.id, "not-a-uuid")
        |> assert_problem(400, :invalid_parameter, [
          not_a_uuid_entry(%{"path" => "user_id"})
        ])

        conn
        |> with_pat(users.admin)
        |> reach(route, organization.id, users.stranger.id)
        |> assert_problem(404, :not_found, [])
      end
    end

    test "a superuser who isn't in it may read and manage it", %{
      conn: conn,
      users: users,
      organization: organization
    } do
      conn = with_pat(conn, users.superuser)

      assert conn |> reach(:show, organization.id, nil) |> json_response(200)

      assert conn
             |> send_json(:patch, "/api/organizations/#{organization.id}", %{
               "name" => "Renamed"
             })
             |> json_response(200)
    end

    test "a token without organizations:write is refused before anything is read",
         %{conn: conn, organization: organization} do
      {conn, _account} = with_service_account(conn, ["projects:write"])

      for route <- [:list | @reads ++ @manages] do
        conn
        |> reach(route, organization.id, Ecto.UUID.generate())
        |> assert_problem(403, :insufficient_scope)
      end
    end
  end

  defp path_of(:show), do: "id"
  defp path_of(:rename), do: "id"
  defp path_of(_route), do: "organization_id"

  defp reach(conn, :list, _id, _user_id), do: get(conn, "/api/organizations")

  defp reach(conn, :show, id, _user_id),
    do: get(conn, "/api/organizations/#{id}")

  defp reach(conn, :rename, id, _user_id),
    do: send_json(conn, :patch, "/api/organizations/#{id}", @body)

  defp reach(conn, :list_members, id, _user_id),
    do: get(conn, "/api/organizations/#{id}/members")

  defp reach(conn, :add, id, _user_id),
    do: send_json(conn, :post, "/api/organizations/#{id}/members", @body)

  defp reach(conn, :change_role, id, user_id),
    do: send_json(conn, :patch, org_member_path(id, user_id), @body)

  defp reach(conn, :remove, id, user_id),
    do: delete(conn, org_member_path(id, user_id))
end
