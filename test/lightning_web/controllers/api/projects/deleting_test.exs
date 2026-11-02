defmodule LightningWeb.API.Projects.DeletingTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiProjectsHelpers
  import Lightning.Factories
  import Lightning.RaceHelpers
  import Lightning.ServiceAccountHelpers

  alias Lightning.Projects.Project
  alias Lightning.Repo

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "deleting" do
    test "the owner's session schedules the project, disables its triggers and records who did it",
         %{conn: conn} do
      owner = insert(:user)
      project = insert(:project, project_users: [%{user: owner, role: :owner}])
      workflow = insert(:simple_workflow, project: project)

      conn = conn |> session_conn(owner) |> delete(~p"/api/projects/#{project}")

      assert conn.status == 204
      assert conn.resp_body == ""

      assert %Project{scheduled_deletion: %DateTime{}} = Repo.reload!(project)
      refute Repo.reload!(hd(workflow.triggers)).enabled

      assert audit_events(project.id) == [
               {"deletion_scheduled", owner.id, :user}
             ]
    end

    test "the service account schedules any project and is recorded as having done it",
         %{conn: conn} do
      project = insert(:project)
      {conn, account} = with_service_account(conn, ["projects:write"])

      assert conn |> delete(~p"/api/projects/#{project}") |> response(204)

      assert Repo.reload!(project).scheduled_deletion

      assert audit_events(project.id) == [
               {"deletion_scheduled", account.uuid, :service_account}
             ]
    end

    test "a sandbox's admin, and an admin of the project at the top of its tree, schedule the sandbox and the sandboxes below it",
         %{conn: conn} do
      sandbox_admin = insert(:user)
      root_admin = insert(:user)

      for user <- [sandbox_admin, root_admin] do
        root =
          insert(:project, project_users: [%{user: root_admin, role: :admin}])

        sandbox =
          insert(:sandbox,
            parent: root,
            project_users: [%{user: sandbox_admin, role: :admin}]
          )

        below = insert(:sandbox, parent: sandbox)

        assert conn
               |> with_pat(user)
               |> delete(~p"/api/projects/#{sandbox}")
               |> response(204)

        assert Repo.reload!(sandbox).scheduled_deletion
        assert Repo.reload!(below).scheduled_deletion
        refute Repo.reload!(root).scheduled_deletion
      end
    end

    test "the service account schedules a sandbox", %{conn: conn} do
      sandbox = insert(:sandbox, parent: insert(:project))
      {conn, _account} = with_service_account(conn, ["projects:write"])

      assert conn |> delete(~p"/api/projects/#{sandbox}") |> response(204)
      assert Repo.reload!(sandbox).scheduled_deletion
    end

    test "a project already scheduled answers 409 and keeps its date", %{
      conn: conn
    } do
      owner = insert(:user)
      project = scheduled_project([%{user: owner, role: :owner}])

      conn
      |> with_pat(owner)
      |> delete(~p"/api/projects/#{project}")
      |> assert_problem(409, :scheduled_for_deletion, [])

      assert Repo.reload!(project).scheduled_deletion ==
               project.scheduled_deletion

      assert audit_events(project.id) == []
    end
  end

  describe "stale writes" do
    test "a project another request deletes mid-delete answers 409 concurrent_edit",
         %{conn: conn} do
      owner = insert(:user)
      project = insert(:project, project_users: [%{user: owner, role: :owner}])

      delete_project_mid_save(project.id)

      conn
      |> with_pat(owner)
      |> delete(~p"/api/projects/#{project}")
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(project)
    end
  end

  describe "who may reach it" do
    test "a caller refused the project gets the same 403 for it, an id that names no project and one that isn't a UUID, and nothing is scheduled",
         %{conn: conn} do
      [admin, editor, viewer, short_of_mfa, stranger] = insert_list(5, :user)
      support = insert(:user, support_user: true)
      superuser = insert(:user, role: :superuser)

      project =
        insert(:project,
          allow_support_access: true,
          project_users: [
            %{user: admin, role: :admin},
            %{user: editor, role: :editor},
            %{user: viewer, role: :viewer}
          ]
        )

      mfa_project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: short_of_mfa, role: :owner}]
        )

      # An editor of a sandbox, even one who is an editor of its root too, is
      # not one of the sandbox's admins.
      sandbox =
        insert(:sandbox,
          parent: project,
          project_users: [%{user: editor, role: :editor}]
        )

      unknown = Ecto.UUID.generate()
      three = &[&1, unknown, "not-a-uuid"]

      refused =
        for(
          user <- [admin, editor, viewer, support],
          do: {user, three.(project.id)}
        ) ++
          [
            {editor, [sandbox.id]},
            {viewer, [sandbox.id]},
            {short_of_mfa, three.(mfa_project.id)},
            {stranger, three.(project.id)},
            {superuser, [project.id, sandbox.id]}
          ]

      for {user, ids} <- refused, id <- ids do
        conn
        |> with_pat(user)
        |> delete(~p"/api/projects/#{id}")
        |> assert_problem(403, :forbidden, [])
      end

      for project <- [project, mfa_project, sandbox] do
        refute Repo.reload!(project).scheduled_deletion
      end
    end

    test "an admin of a sandbox's root who hasn't met the root's MFA requirement is refused",
         %{conn: conn} do
      root_admin = insert(:user, mfa_enabled: false)

      root =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: root_admin, role: :admin}]
        )

      sandbox = insert(:sandbox, parent: root)

      conn
      |> with_pat(root_admin)
      |> delete(~p"/api/projects/#{sandbox}")
      |> assert_problem(403, :forbidden, [])

      refute Repo.reload!(sandbox).scheduled_deletion
    end

    test "a superuser or the service account gets 400 for an id that isn't a UUID, and 404 for one that names no project",
         %{conn: conn} do
      {service_account_conn, _account} =
        with_service_account(conn, ["projects:write"])

      superuser_conn = with_pat(conn, insert(:user, role: :superuser))

      for caller <- [superuser_conn, service_account_conn] do
        caller
        |> delete(~p"/api/projects/#{Ecto.UUID.generate()}")
        |> assert_problem(404, :not_found, [])

        caller
        |> delete(~p"/api/projects/not-a-uuid")
        |> assert_problem(400, :invalid_parameter, [
          not_a_uuid_entry(%{"path" => "id"})
        ])
      end
    end

    test "a scheduled project is 403 to a caller who may not delete it, and 409 to one who may",
         %{conn: conn} do
      [owner, admin] = insert_list(2, :user)

      project =
        scheduled_project([
          %{user: owner, role: :owner},
          %{user: admin, role: :admin}
        ])

      conn
      |> with_pat(admin)
      |> delete(~p"/api/projects/#{project}")
      |> assert_problem(403, :forbidden, [])

      conn
      |> with_pat(owner)
      |> delete(~p"/api/projects/#{project}")
      |> assert_problem(409, :scheduled_for_deletion, [])
    end
  end

  defp audit_events(project_id) do
    from(a in Lightning.Auditing.Audit,
      where: a.item_id == ^project_id,
      select: {a.event, a.actor_id, a.actor_type},
      order_by: a.inserted_at
    )
    |> Repo.all()
  end
end
