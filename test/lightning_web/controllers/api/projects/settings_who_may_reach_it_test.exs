defmodule LightningWeb.API.Projects.SettingsWhoMayReachItTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.ApiProjectsHelpers
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  alias Lightning.Repo

  # A body none of the routes accept, so a refusal that comes first is visible.
  @body ~s({"nonsense": 1})
  @routes ["data_retention", "mfa_requirement", "support_access"]

  setup %{conn: conn} do
    {:ok,
     conn:
       conn
       |> put_req_header("accept", "application/json")
       |> put_req_header("content-type", "application/json")}
  end

  describe "who may reach it" do
    test "a caller refused the project gets the same 403 for it, an id that names no project and one that isn't a UUID, on every settings route",
         %{conn: conn} do
      [editor, viewer, short_of_mfa, stranger] = insert_list(4, :user)
      support = insert(:user, support_user: true)
      superuser = insert(:user, role: :superuser)

      project =
        insert(:project,
          allow_support_access: true,
          project_users: [
            %{user: editor, role: :editor},
            %{user: viewer, role: :viewer}
          ]
        )

      mfa_project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: short_of_mfa, role: :owner}]
        )

      unknown = Ecto.UUID.generate()
      three = &[&1, unknown, "not-a-uuid"]

      refused = [
        {editor, three.(project.id)},
        {viewer, three.(project.id)},
        {support, three.(project.id)},
        {short_of_mfa, three.(mfa_project.id)},
        {stranger, three.(project.id)},
        {superuser, [project.id]}
      ]

      for {user, ids} <- refused, id <- ids, route <- @routes do
        conn
        |> with_pat(user)
        |> put("/api/projects/#{id}/#{route}", @body)
        |> assert_problem(403, :forbidden, [])
      end

      for written <- [project, mfa_project] do
        assert Repo.reload!(written).updated_at == written.updated_at
      end
    end

    test "an owner or an admin reaches every settings route", %{conn: conn} do
      for role <- [:owner, :admin] do
        user = insert(:user)
        project = insert(:project, project_users: [%{user: user, role: role}])

        for route <- @routes do
          conn
          |> with_pat(user)
          |> put("/api/projects/#{project.id}/#{route}", @body)
          |> assert_problem(422, :invalid)
        end
      end
    end

    test "a superuser or the service account gets 400 for an id that isn't a UUID, and 404 for one that names no project",
         %{conn: conn} do
      {service_account_conn, _account} =
        with_service_account(conn, ["projects:write"])

      superuser_conn = with_pat(conn, insert(:user, role: :superuser))

      for caller <- [superuser_conn, service_account_conn], route <- @routes do
        caller
        |> put("/api/projects/#{Ecto.UUID.generate()}/#{route}", @body)
        |> assert_problem(404, :not_found, [])

        caller
        |> put("/api/projects/not-a-uuid/#{route}", @body)
        |> assert_problem(400, :invalid_parameter, [
          not_a_uuid_entry(%{"path" => "id"})
        ])
      end
    end

    test "a project scheduled for deletion is 403 to a stranger and 409 to its owner or the service account",
         %{conn: conn} do
      {service_account_conn, _account} =
        with_service_account(conn, ["projects:write"])

      [owner, stranger] = insert_list(2, :user)
      project = scheduled_project([%{user: owner, role: :owner}])

      for route <- @routes,
          {caller, status, code} <- [
            {with_pat(conn, stranger), 403, :forbidden},
            {with_pat(conn, owner), 409, :scheduled_for_deletion},
            {service_account_conn, 409, :scheduled_for_deletion}
          ] do
        caller
        |> put("/api/projects/#{project.id}/#{route}", @body)
        |> assert_problem(status, code, [])
      end
    end
  end
end
