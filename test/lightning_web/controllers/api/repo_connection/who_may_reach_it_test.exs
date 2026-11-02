defmodule LightningWeb.API.RepoConnection.WhoMayReachItTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.ApiProjectsHelpers
  import LightningWeb.ApiRepoConnectionHelpers
  import Mox, only: [verify_on_exit!: 1]

  alias Lightning.Repo
  alias Lightning.VersionControl.ProjectRepoConnection

  # No GitHub expectations are set, so any call to GitHub fails the test.
  setup :verify_on_exit!

  setup %{conn: conn} do
    [editor, viewer, stranger] = for _ <- 1..3, do: github_user()
    unenrolled = github_user(mfa_enabled: false)

    project =
      insert(:project,
        project_users: [
          %{user: editor, role: :editor},
          %{user: viewer, role: :viewer}
        ]
      )

    mfa_project =
      insert(:project,
        requires_mfa: true,
        project_users: [%{user: unenrolled, role: :owner}]
      )

    for p <- [project, mfa_project],
        do: insert(:project_repo_connection, project: p)

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     editor: editor,
     viewer: viewer,
     stranger: stranger,
     unenrolled: unenrolled,
     project: project,
     mfa_project: mfa_project}
  end

  @body %{"nonsense" => 1}

  defp reach(conn, :show, project_id),
    do: get(conn, ~p"/api/projects/#{project_id}/repo_connection")

  defp reach(conn, :update, project_id),
    do: put_repo_connection(conn, project_id, @body)

  defp reach(conn, :delete, project_id),
    do: delete(conn, ~p"/api/projects/#{project_id}/repo_connection")

  defp reach(conn, :sync, project_id),
    do: sync_repo_connection(conn, project_id, @body)

  @actions [:show, :update, :delete, :sync]

  describe "who may reach it" do
    test "a caller without standing, short of MFA, or whose role the route refuses gets the same 403 for an existing, unknown or malformed project, and nothing changes",
         ctx do
      rows =
        for {user, project, actions} <- [
              {ctx.stranger, ctx.project, @actions},
              {ctx.unenrolled, ctx.mfa_project, @actions},
              {ctx.viewer, ctx.project, [:update, :delete, :sync]},
              {ctx.editor, ctx.project, [:update, :delete]}
            ],
            action <- actions,
            project_id <- [project.id, Ecto.UUID.generate(), "not-a-uuid"],
            do: {user, action, project_id}

      for {user, action, project_id} <- rows do
        ctx.conn
        |> with_pat(user)
        |> reach(action, project_id)
        |> assert_problem(403, :forbidden, [])
      end

      assert Repo.aggregate(ProjectRepoConnection, :count) == 2
    end

    test "a member who may reach a project with no connection hears 404",
         %{conn: conn, viewer: viewer} do
      project = insert(:project, project_users: [%{user: viewer, role: :viewer}])

      conn
      |> with_pat(viewer)
      |> reach(:show, project.id)
      |> assert_problem(404, :not_found, [])
    end

    test "a superuser who isn't a member is refused, and hears 404 or 400 for a project id that names nothing",
         %{conn: conn, project: project} do
      superuser = with_pat(conn, github_user(role: :superuser))

      for action <- @actions do
        superuser
        |> reach(action, project.id)
        |> assert_problem(403, :forbidden, [])

        superuser
        |> reach(action, Ecto.UUID.generate())
        |> assert_problem(404, :not_found, [])

        superuser
        |> reach(action, "not-a-uuid")
        |> assert_problem(400, :invalid_parameter, [
          not_a_uuid_entry(%{"path" => "project_id"})
        ])
      end
    end

    test "a project scheduled for deletion is 409 to its owner and 403 to a stranger",
         %{conn: conn, stranger: stranger} do
      owner = github_user()
      project = scheduled_project([%{user: owner, role: :owner}])
      insert(:project_repo_connection, project: project)

      for action <- @actions do
        conn
        |> with_pat(owner)
        |> reach(action, project.id)
        |> assert_problem(409, :scheduled_for_deletion, [])

        conn
        |> with_pat(stranger)
        |> reach(action, project.id)
        |> assert_problem(403, :forbidden, [])
      end
    end
  end
end
