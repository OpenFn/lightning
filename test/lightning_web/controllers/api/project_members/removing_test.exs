defmodule LightningWeb.API.ProjectMembers.RemovingTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiProjectMembersHelpers
  import LightningWeb.ApiProjectsHelpers
  import Lightning.Factories
  import Lightning.RaceHelpers
  import Lightning.ServiceAccountHelpers

  alias Lightning.Repo

  setup %{conn: conn} do
    [owner, admin, editor] = insert_list(3, :user)

    project =
      insert(:project,
        project_users: [
          %{user: owner, role: :owner},
          %{user: admin, role: :admin},
          %{user: editor, role: :editor}
        ]
      )

    %{
      conn: put_req_header(conn, "accept", "application/json"),
      owner: owner,
      admin: admin,
      editor: editor,
      project: project
    }
  end

  describe "removing a member" do
    test "an admin's session removes a member, revokes the project's access to their credentials and records who did it",
         %{conn: conn, admin: admin, editor: editor, project: project} do
      credential = insert(:credential, user: editor)
      insert(:project_credential, project: project, credential: credential)

      conn =
        conn
        |> session_conn(admin)
        |> delete(member_path(project.id, editor.id))

      assert conn.status == 204
      assert conn.resp_body == ""

      refute role_of(project.id, editor.id)

      refute Repo.get_by(Lightning.Projects.ProjectCredential,
               project_id: project.id,
               credential_id: credential.id
             )

      assert Repo.reload(credential)
      assert audit_events(project.id) == [{"collaborator_removed", admin.id}]
    end

    test "the service account removes a member", %{
      conn: conn,
      editor: editor,
      project: project
    } do
      {conn, account} = with_service_account(conn, ["projects:write"])

      assert conn |> delete(member_path(project.id, editor.id)) |> response(204)

      refute role_of(project.id, editor.id)
      assert audit_events(project.id) == [{"collaborator_removed", account.uuid}]
    end
  end

  describe "refusals" do
    test "a user who isn't a member answers 404", %{
      conn: conn,
      admin: admin,
      project: project
    } do
      for user_id <- [insert(:user).id, Ecto.UUID.generate()] do
        conn
        |> with_pat(admin)
        |> delete(member_path(project.id, user_id))
        |> assert_problem(404, :not_found, [])
      end
    end

    test "the owner answers 422 and stays", %{
      conn: conn,
      owner: owner,
      admin: admin,
      project: project
    } do
      for caller <- [owner, admin] do
        conn
        |> with_pat(caller)
        |> delete(member_path(project.id, owner.id))
        |> assert_problem(422, :invalid, [
          %{
            "path" => "user_id",
            "code" => "one_owner",
            "detail" => "is the project's owner, who can't be removed"
          }
        ])
      end

      assert role_of(project.id, owner.id) == :owner
    end

    test "an admin removing themself answers 422 and stays",
         %{conn: conn, admin: admin, project: project} do
      conn
      |> with_pat(admin)
      |> delete(member_path(project.id, admin.id))
      |> assert_problem(422, :invalid, [
        %{
          "path" => "user_id",
          "code" => "not_allowed",
          "detail" => "is you, and you can't remove yourself from a project"
        }
      ])

      assert role_of(project.id, admin.id) == :admin
    end

    test "an admin of the project a sandbox is under answers 422 and stays in the sandbox",
         %{conn: conn, admin: admin, project: project} do
      sandbox_owner = insert(:user)

      sandbox =
        insert(:sandbox,
          parent: project,
          project_users: [
            %{user: sandbox_owner, role: :owner},
            %{user: admin, role: :admin}
          ]
        )

      conn
      |> with_pat(sandbox_owner)
      |> delete(member_path(sandbox.id, admin.id))
      |> assert_problem(422, :invalid, [
        %{
          "path" => "user_id",
          "code" => "not_allowed",
          "detail" => "is an owner or admin of a project this sandbox is under"
        }
      ])

      assert role_of(sandbox.id, admin.id) == :admin
    end
  end

  describe "stale writes" do
    test "a member another request removes mid-removal answers 409 concurrent_edit and stays removed, with the other request's audit event",
         %{
           conn: conn,
           owner: owner,
           admin: admin,
           editor: editor,
           project: project
         } do
      # After the route reads the membership, before it writes.
      after_first_query("project_users", editor.id, fn _user_id ->
        Lightning.Projects.delete_project_user!(
          Repo.get_by!(Lightning.Projects.ProjectUser,
            project_id: project.id,
            user_id: editor.id
          ),
          owner
        )
      end)

      conn
      |> with_pat(admin)
      |> delete(member_path(project.id, editor.id))
      |> assert_problem(409, :concurrent_edit, [])

      refute role_of(project.id, editor.id)
      assert audit_events(project.id) == [{"collaborator_removed", owner.id}]
    end

    test "a project another request deletes mid-removal answers 409 concurrent_edit",
         %{conn: conn, admin: admin, editor: editor, project: project} do
      after_first_query("project_users", editor.id, fn _user_id ->
        Repo.query!("DELETE FROM project_users WHERE project_id = $1", [
          Ecto.UUID.dump!(project.id)
        ])

        Repo.delete!(project)
      end)

      conn
      |> with_pat(admin)
      |> delete(member_path(project.id, editor.id))
      |> assert_problem(409, :concurrent_edit, [])

      refute Repo.reload(project)
    end
  end
end
