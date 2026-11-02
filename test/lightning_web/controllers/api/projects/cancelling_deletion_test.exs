defmodule LightningWeb.API.Projects.CancellingDeletionTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiProjectsHelpers
  import Lightning.Factories
  import Lightning.RaceHelpers
  import Lightning.ServiceAccountHelpers

  alias Lightning.Extensions.Message
  alias Lightning.Repo

  setup %{conn: conn} do
    {:ok, conn: put_req_header(conn, "accept", "application/json")}
  end

  describe "cancelling a deletion" do
    test "the owner's session cancels it, answers with the project and records who did it",
         %{conn: conn} do
      owner = insert(:user)
      project = scheduled_project([%{user: owner, role: :owner}])

      conn =
        conn
        |> session_conn(owner)
        |> delete(~p"/api/projects/#{project}/scheduled_deletion")

      self_link = "#{LightningWeb.Endpoint.url()}/api/projects/#{project.id}"

      assert json_response(conn, 200) == %{
               "data" => %{
                 "type" => "projects",
                 "id" => project.id,
                 "attributes" => %{
                   "name" => project.name,
                   "description" => project.description,
                   "members" => [%{"email" => owner.email, "role" => "owner"}]
                 },
                 "relationships" => %{},
                 "links" => %{"self" => self_link}
               },
               "included" => [],
               "links" => %{
                 "self" =>
                   "#{LightningWeb.Endpoint.url()}/api/projects/#{project.id}/scheduled_deletion"
               }
             }

      refute Repo.reload!(project).scheduled_deletion

      assert audit_events(project.id) == [
               {"deletion_cancelled", owner.id, :user}
             ]
    end

    test "the service account cancels a project's or a sandbox's deletion", %{
      conn: conn
    } do
      {conn, _account} = with_service_account(conn, ["projects:write"])
      root = insert(:project)

      for project <- [
            scheduled_project(),
            insert(:sandbox, parent: root, scheduled_deletion: now())
          ] do
        assert conn
               |> delete(~p"/api/projects/#{project}/scheduled_deletion")
               |> json_response(200)

        refute Repo.reload!(project).scheduled_deletion
      end
    end

    test "an admin of a sandbox's root cancels the sandbox's deletion and that of the sandboxes below it",
         %{conn: conn} do
      root_admin = insert(:user)
      root = insert(:project, project_users: [%{user: root_admin, role: :admin}])
      sandbox = insert(:sandbox, parent: root, scheduled_deletion: now())
      below = insert(:sandbox, parent: sandbox, scheduled_deletion: now())

      assert conn
             |> with_pat(root_admin)
             |> delete(~p"/api/projects/#{sandbox}/scheduled_deletion")
             |> json_response(200)

      refute Repo.reload!(sandbox).scheduled_deletion
      refute Repo.reload!(below).scheduled_deletion
    end

    test "a project that isn't scheduled answers 404", %{conn: conn} do
      owner = insert(:user)
      project = insert(:project, project_users: [%{user: owner, role: :owner}])

      conn
      |> with_pat(owner)
      |> delete(~p"/api/projects/#{project}/scheduled_deletion")
      |> assert_problem(404, :not_found, [])

      assert audit_events(project.id) == []
    end

    test "restoring a sandbox the plan has no room for answers 402 and leaves it scheduled",
         %{conn: conn} do
      root_owner = insert(:user)
      root = insert(:project, project_users: [%{user: root_owner, role: :owner}])

      for reason <- [:exceeds_limit, :too_many_sandboxes] do
        sandbox = insert(:sandbox, parent: root, scheduled_deletion: now())

        Mox.stub(Lightning.Extensions.MockUsageLimiter, :limit_action, fn
          %{type: :new_sandbox}, _context ->
            {:error, reason, %Message{text: "No more sandboxes"}}
        end)

        conn
        |> with_pat(root_owner)
        |> delete(~p"/api/projects/#{sandbox}/scheduled_deletion")
        |> assert_problem(402, :exceeds_limit, [])

        assert Repo.reload!(sandbox).scheduled_deletion
      end
    end
  end

  describe "stale writes" do
    test "a project another request deletes mid-cancel answers 409 concurrent_edit",
         %{conn: conn} do
      owner = insert(:user)
      project = scheduled_project([%{user: owner, role: :owner}])

      delete_project_mid_save(project.id)

      conn
      |> with_pat(owner)
      |> delete(~p"/api/projects/#{project}/scheduled_deletion")
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(project)
    end
  end

  describe "who may reach it" do
    test "a caller refused the project gets the same 403 for it, an id that names no project and one that isn't a UUID, and the deletion stands",
         %{conn: conn} do
      [admin, editor, short_of_mfa, stranger] = insert_list(4, :user)
      superuser = insert(:user, role: :superuser)

      project =
        scheduled_project([
          %{user: admin, role: :admin},
          %{user: editor, role: :editor}
        ])

      mfa_project =
        insert(:project,
          requires_mfa: true,
          scheduled_deletion: now(),
          project_users: [%{user: short_of_mfa, role: :owner}]
        )

      unknown = Ecto.UUID.generate()
      three = &[&1, unknown, "not-a-uuid"]

      refused = [
        {admin, three.(project.id)},
        {editor, three.(project.id)},
        {short_of_mfa, three.(mfa_project.id)},
        {stranger, three.(project.id)},
        {superuser, [project.id]}
      ]

      for {user, ids} <- refused, id <- ids do
        conn
        |> with_pat(user)
        |> delete(~p"/api/projects/#{id}/scheduled_deletion")
        |> assert_problem(403, :forbidden, [])
      end

      assert Repo.reload!(project).scheduled_deletion
      assert Repo.reload!(mfa_project).scheduled_deletion
    end

    test "a superuser or the service account gets 400 for an id that isn't a UUID, and 404 for one that names no project",
         %{conn: conn} do
      {service_account_conn, _account} =
        with_service_account(conn, ["projects:write"])

      superuser_conn = with_pat(conn, insert(:user, role: :superuser))

      for caller <- [superuser_conn, service_account_conn] do
        caller
        |> delete(~p"/api/projects/#{Ecto.UUID.generate()}/scheduled_deletion")
        |> assert_problem(404, :not_found, [])

        caller
        |> delete(~p"/api/projects/not-a-uuid/scheduled_deletion")
        |> assert_problem(400, :invalid_parameter, [
          not_a_uuid_entry(%{"path" => "id"})
        ])
      end
    end
  end

  defp now, do: DateTime.utc_now() |> DateTime.truncate(:second)

  defp audit_events(project_id) do
    from(a in Lightning.Auditing.Audit,
      where: a.item_id == ^project_id,
      select: {a.event, a.actor_id, a.actor_type}
    )
    |> Repo.all()
  end
end
