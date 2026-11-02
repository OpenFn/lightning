defmodule LightningWeb.API.Sandboxes.WhoMayReachItTest do
  use LightningWeb.ConnCase, async: true

  import Ecto.Query
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.ApiProjectsHelpers
  import LightningWeb.ApiSandboxesHelpers
  import Lightning.Factories

  alias Lightning.Projects.Project
  alias Lightning.Repo

  setup %{conn: conn} do
    [owner, editor, viewer, sandbox_owner, stranger, unenrolled] =
      insert_list(6, :user)

    {parent, sandbox} = project_with_sandbox(owner, sandbox_owner)

    insert(:project_user, project: parent, user: editor, role: :editor)
    insert(:project_user, project: parent, user: viewer, role: :viewer)

    mfa_parent =
      insert(:project,
        requires_mfa: true,
        project_users: [%{user: unenrolled, role: :owner}]
      )

    mfa_sandbox =
      insert(:project,
        parent: mfa_parent,
        requires_mfa: true,
        project_users: [%{user: unenrolled, role: :owner}]
      )

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     owner: owner,
     editor: editor,
     viewer: viewer,
     stranger: stranger,
     unenrolled: unenrolled,
     parent: parent,
     sandbox: sandbox,
     mfa_parent: mfa_parent,
     mfa_sandbox: mfa_sandbox}
  end

  # A body no route would accept, so a refusal that comes first is visible.
  @body %{"nonsense" => 1}

  defp reach(conn, :index, project_id, _id),
    do: get(conn, ~p"/api/projects/#{project_id}/sandboxes")

  defp reach(conn, :update, project_id, id),
    do: put_sandbox(conn, project_id, id, @body)

  defp reach(conn, :merge_preview, project_id, id),
    do: preview_merge(conn, project_id, id, @body)

  defp reach(conn, :merge, project_id, id),
    do: merge_sandbox(conn, project_id, id, @body)

  describe "who may reach it" do
    test "a caller without standing, short of MFA, or whose role the route refuses gets the same 403 for an existing, unknown or malformed id",
         ctx do
      %{conn: conn, parent: parent, sandbox: sandbox} = ctx
      unknown = Ecto.UUID.generate()

      # The caller, the project in the path, the sandbox, and the routes.
      rows =
        for {user, project, existing, actions} <- [
              {ctx.stranger, parent, sandbox,
               [:index, :update, :merge_preview, :merge]},
              {ctx.unenrolled, ctx.mfa_parent, ctx.mfa_sandbox,
               [:index, :update, :merge_preview, :merge]},
              {ctx.viewer, parent, sandbox, [:update]}
            ],
            action <- actions,
            project_id <- [project.id, unknown, "not-a-uuid"],
            id <- [existing.id, Ecto.UUID.generate(), "not-a-uuid"],
            do: {user, action, project_id, id}

      for {user, action, project_id, id} <- rows do
        conn
        |> with_pat(user)
        |> reach(action, project_id, id)
        |> assert_problem(403, :forbidden, [])
      end

      refute Repo.exists?(
               from(p in Project,
                 where: p.parent_id == ^parent.id and p.id != ^sandbox.id
               )
             )
    end

    test "a member of the parent who may not manage the sandbox is refused a merge of an existing one, and hears 404 or 400 for any other id",
         %{
           conn: conn,
           editor: editor,
           viewer: viewer,
           parent: parent,
           sandbox: sandbox
         } do
      for user <- [editor, viewer], action <- [:merge_preview, :merge] do
        caller = with_pat(conn, user)

        caller
        |> reach(action, parent.id, sandbox.id)
        |> assert_problem(403, :forbidden, [])

        caller
        |> reach(action, parent.id, Ecto.UUID.generate())
        |> assert_problem(404, :not_found, [])

        caller
        |> reach(action, parent.id, "not-a-uuid")
        |> assert_problem(400, :invalid_parameter, [
          not_a_uuid_entry(%{"path" => "id"})
        ])
      end
    end

    test "a sandbox of another project counts as missing under this one",
         %{conn: conn, owner: owner, parent: parent} do
      {_other_parent, other_sandbox} = project_with_sandbox(insert(:user), owner)

      for action <- [:merge_preview, :merge] do
        conn
        |> with_pat(owner)
        |> reach(action, parent.id, other_sandbox.id)
        |> assert_problem(404, :not_found, [])
      end
    end

    test "creating under a malformed id is 400, an id held by another project is 409 to one who may create here and 403 to one who may not",
         %{conn: conn, editor: editor, viewer: viewer, parent: parent} do
      elsewhere = insert(:project)

      conn
      |> with_pat(editor)
      |> put_sandbox(parent.id, "not-a-uuid", %{"name" => "staging"})
      |> assert_problem(400, :invalid_parameter, [
        not_a_uuid_entry(%{"path" => "id"})
      ])

      conn
      |> with_pat(editor)
      |> put_sandbox(parent.id, elsewhere.id, %{"name" => "staging"})
      |> assert_problem(409, :id_taken, [])

      conn
      |> with_pat(viewer)
      |> put_sandbox(parent.id, elsewhere.id, %{"name" => "staging"})
      |> assert_problem(403, :forbidden, [])

      assert Repo.reload!(elsewhere).parent_id == nil
    end

    test "an editor who may create sandboxes but not manage this one is refused a PUT on its id",
         %{conn: conn, editor: editor, parent: parent, sandbox: sandbox} do
      conn
      |> with_pat(editor)
      |> put_sandbox(parent.id, sandbox.id, %{"name" => "staging"})
      |> assert_problem(403, :forbidden, [])
    end

    test "a parent scheduled for deletion is 409 to its owner and 403 to a stranger",
         %{conn: conn, owner: owner, stranger: stranger} do
      parent =
        scheduled_project([%{user: owner, role: :owner}])

      sandbox =
        insert(:project,
          parent: parent,
          project_users: [%{user: owner, role: :owner}]
        )

      for action <- [:index, :update, :merge_preview, :merge] do
        conn
        |> with_pat(owner)
        |> reach(action, parent.id, sandbox.id)
        |> assert_problem(409, :scheduled_for_deletion, [])

        conn
        |> with_pat(stranger)
        |> reach(action, parent.id, sandbox.id)
        |> assert_problem(403, :forbidden, [])
      end
    end

    test "a sandbox scheduled for deletion is 409 to its owner, who can neither preview nor make a merge of it",
         %{conn: conn, owner: owner, parent: parent, sandbox: sandbox} do
      sandbox
      |> Ecto.Changeset.change(
        scheduled_deletion: DateTime.utc_now() |> DateTime.truncate(:second)
      )
      |> Repo.update!()

      for action <- [:merge_preview, :merge] do
        conn
        |> with_pat(owner)
        |> reach(action, parent.id, sandbox.id)
        |> assert_problem(409, :scheduled_for_deletion, [])
      end
    end

    test "a superuser who isn't a member is refused, and hears 404 or 400 for a project id that names nothing",
         %{conn: conn, parent: parent, sandbox: sandbox} do
      superuser = with_pat(conn, insert(:user, role: :superuser))

      for action <- [:index, :update, :merge_preview, :merge] do
        superuser
        |> reach(action, parent.id, sandbox.id)
        |> assert_problem(403, :forbidden, [])

        superuser
        |> reach(action, Ecto.UUID.generate(), sandbox.id)
        |> assert_problem(404, :not_found, [])

        superuser
        |> reach(action, "not-a-uuid", sandbox.id)
        |> assert_problem(400, :invalid_parameter, [
          not_a_uuid_entry(%{"path" => "project_id"})
        ])
      end
    end
  end
end
