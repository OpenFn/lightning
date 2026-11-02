defmodule LightningWeb.API.RepoConnection.ConnectingTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Lightning.GithubHelpers
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiProjectsHelpers
  import LightningWeb.ApiRepoConnectionHelpers
  import Mox, only: [verify_on_exit!: 1]

  alias Lightning.Extensions.Message
  alias Lightning.Extensions.MockUsageLimiter
  alias Lightning.Repo
  alias Lightning.VersionControl.ProjectRepoConnection

  setup :verify_on_exit!

  setup %{conn: conn} do
    admin = github_user()
    project = insert(:project, project_users: [%{user: admin, role: :admin}])

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     admin: admin,
     project: project}
  end

  @body %{
    "github_installation_id" => "1234",
    "repo" => "someaccount/somerepo",
    "branch" => "somebranch"
  }

  defp body(repo_connection, branch) do
    self =
      "#{LightningWeb.Endpoint.url()}/api/projects/#{repo_connection.project_id}/repo_connection"

    %{
      "data" => %{
        "type" => "repo_connections",
        "id" => repo_connection.id,
        "attributes" => %{
          "repo" => repo(),
          "branch" => branch,
          "github_installation_id" => installation_id(),
          "config_path" => ProjectRepoConnection.config_path(repo_connection),
          "verified" => true,
          "problems" => [],
          "inserted_at" => DateTime.to_iso8601(repo_connection.inserted_at),
          "updated_at" => DateTime.to_iso8601(repo_connection.updated_at)
        },
        "relationships" => %{},
        "links" => %{"self" => self}
      },
      "links" => %{"self" => self}
    }
  end

  defp connection_of(project),
    do: Repo.get_by(ProjectRepoConnection, project_id: project.id)

  defp existing_connection(project, attrs \\ []) do
    insert(
      :project_repo_connection,
      Keyword.merge(
        [
          project: project,
          repo: repo(),
          branch: "somebranch",
          github_installation_id: installation_id()
        ],
        attrs
      )
    )
  end

  describe "connecting a repo" do
    test "an admin connects the project on a session token, answering 201, writing to the repo and starting a sync",
         %{conn: conn, admin: admin, project: project} do
      expect_connecting(project.id, "somebranch")

      conn =
        conn
        |> session_conn(admin)
        |> put_repo_connection(project.id, @body)

      repo_connection = connection_of(project)
      assert json_response(conn, 201) == body(repo_connection, "somebranch")
    end

    test "a deploy connection names the config already in the repo and starts no sync",
         %{conn: conn, admin: admin, project: project} do
      expect_connecting(project.id, "somebranch",
        sync: false,
        config_blob: false
      )

      conn
      |> with_pat(admin)
      |> put_repo_connection(
        project.id,
        Map.merge(@body, %{
          "sync_direction" => "deploy",
          "config_path" => "./config.json"
        })
      )
      |> json_response(201)

      assert connection_of(project).config_path == "./config.json"
    end

    test "the same installation, repo, branch and config path reconnects, answering 200 and writing to the repo again",
         %{conn: conn, admin: admin, project: project} do
      existing = existing_connection(project)
      expect_connecting(project.id, "somebranch")

      conn =
        conn
        |> with_pat(admin)
        |> put_repo_connection(project.id, @body)

      assert json_response(conn, 200) == body(existing, "somebranch")
      assert connection_of(project).id == existing.id
    end

    test "another branch replaces the connection, answering 200, and cleans up the old branch but keeps the shared secret",
         %{conn: conn, admin: admin, project: project} do
      existing = existing_connection(project, branch: "oldbranch")
      expect_connecting(project.id, "somebranch")
      expect_cleaning_up(project.id, keep_secret: true)

      conn =
        conn
        |> with_pat(admin)
        |> put_repo_connection(project.id, @body)

      replaced = connection_of(project)
      assert json_response(conn, 200) == body(replaced, "somebranch")
      refute replaced.id == existing.id
      refute Repo.get(ProjectRepoConnection, existing.id)
    end

    test "a body it can't use answers one 422 with every problem in it, and nothing is saved",
         %{conn: conn, admin: admin, project: project} do
      caller = with_pat(conn, admin)

      for {body, entries} <- [
            {%{"extra" => 1, "sync_direction" => "sideways"},
             [
               %{
                 "pointer" => "#/extra",
                 "code" => "unknown_key",
                 "detail" => "is not accepted"
               },
               %{
                 "pointer" => "#/sync_direction",
                 "code" => "not_allowed",
                 "detail" => "is invalid"
               },
               %{
                 "pointer" => "#/github_installation_id",
                 "code" => "required",
                 "detail" => "can't be blank"
               },
               %{
                 "pointer" => "#/repo",
                 "code" => "required",
                 "detail" => "can't be blank"
               },
               %{
                 "pointer" => "#/branch",
                 "code" => "required",
                 "detail" => "can't be blank"
               }
             ]},
            {Map.put(@body, "sync_direction", "deploy"),
             [
               %{
                 "pointer" => "#/config_path",
                 "code" => "required",
                 "detail" => "you must specify a path to an existing config file"
               }
             ]},
            {Map.put(@body, "config_path", "../elsewhere.json"),
             [
               %{
                 "pointer" => "#/config_path",
                 "code" => "not_allowed",
                 "detail" => "must stay inside the repository"
               }
             ]}
          ] do
        caller
        |> put_repo_connection(project.id, body)
        |> assert_problem(422, :invalid, entries)
      end

      refute connection_of(project)
    end

    test "a branch another project in the family uses answers 422 at branch",
         %{conn: conn, admin: admin, project: project} do
      sandbox =
        insert(:project,
          parent: project,
          project_users: [%{user: admin, role: :admin}]
        )

      existing_connection(project)

      conn
      |> with_pat(admin)
      |> put_repo_connection(sandbox.id, @body)
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/branch",
          "code" => "tree_branch_conflict",
          "detail" =>
            "this branch is already linked to another project in the same project family; use a different branch"
        }
      ])

      refute connection_of(sandbox)
    end

    test "a plan without GitHub sync answers 402, and nothing is saved or written",
         %{conn: conn, admin: admin, project: project} do
      for reason <- [:github_sync_not_allowed, :exceeds_limit] do
        Mox.stub(MockUsageLimiter, :limit_action, fn
          %{type: :github_sync}, _context ->
            {:error, reason, %Message{text: "No"}}

          _action, _context ->
            :ok
        end)

        conn
        |> with_pat(admin)
        |> put_repo_connection(project.id, @body)
        |> assert_problem(402, :exceeds_limit, [])
      end

      refute connection_of(project)
    end

    test "GitHub refusing a write answers 503, and nothing is saved",
         %{conn: conn, admin: admin, project: project} do
      expect_get_repo(repo(), 500, %{"message" => "Server Error"})

      conn
      |> with_pat(admin)
      |> put_repo_connection(project.id, @body)
      |> assert_problem(503, :service_unavailable, [])

      refute connection_of(project)
    end

    test "GitHub refusing a replacement answers 503 and keeps the old connection",
         %{conn: conn, admin: admin, project: project} do
      existing = existing_connection(project, branch: "oldbranch")
      expect_get_repo(repo(), 500, %{"message" => "Server Error"})

      conn
      |> with_pat(admin)
      |> put_repo_connection(project.id, @body)
      |> assert_problem(503, :service_unavailable, [])

      assert connection_of(project).id == existing.id
    end

    test "a project whose workflows collide when exported answers 409 before anything is written",
         %{conn: conn, admin: admin, project: project} do
      insert(:simple_workflow, project: project, name: "My Flow")
      insert(:simple_workflow, project: project, name: "My-Flow")

      conn
      |> with_pat(admin)
      |> put_repo_connection(project.id, @body)
      |> assert_problem(409, :export_conflict, [])

      refute connection_of(project)
    end

    test "a caller who hasn't connected a GitHub account is refused, after the body is read as an object",
         %{conn: conn, project: project} do
      owner = insert(:user)
      insert(:project_user, project: project, user: owner, role: :owner)

      conn
      |> with_pat(owner)
      |> put_repo_connection(project.id, @body)
      |> assert_problem(403, :forbidden, [])

      refute connection_of(project)
    end
  end

  describe "disconnecting a repo" do
    test "an admin disconnects on a session token, answering 204, and Lightning cleans up the repo",
         %{conn: conn, admin: admin, project: project} do
      existing = existing_connection(project)
      expect_cleaning_up(project.id)

      conn =
        conn
        |> session_conn(admin)
        |> delete(~p"/api/projects/#{project.id}/repo_connection")

      assert response(conn, 204) == ""
      refute Repo.get(ProjectRepoConnection, existing.id)
    end

    test "a project with no connection answers 404", %{
      conn: conn,
      admin: admin,
      project: project
    } do
      conn
      |> with_pat(admin)
      |> delete(~p"/api/projects/#{project.id}/repo_connection")
      |> assert_problem(404, :not_found, [])
    end
  end

  describe "stale writes" do
    test "a connection another request removes mid-delete answers 409", %{
      conn: conn,
      admin: admin,
      project: project
    } do
      existing_connection(project)

      Lightning.RaceHelpers.after_first_query(
        "project_repo_connections",
        project.id,
        fn id ->
          Repo.query!(
            "DELETE FROM project_repo_connections WHERE project_id = $1",
            [id]
          )
        end
      )

      conn
      |> with_pat(admin)
      |> delete(~p"/api/projects/#{project.id}/repo_connection")
      |> assert_problem(409, :concurrent_edit, [])

      refute connection_of(project)
    end

    test "a connection another request removes mid-replace answers 409, and nothing is saved",
         %{conn: conn, admin: admin, project: project} do
      existing_connection(project, branch: "oldbranch")

      Lightning.RaceHelpers.after_first_query(
        "project_repo_connections",
        project.id,
        fn id ->
          Repo.query!(
            "DELETE FROM project_repo_connections WHERE project_id = $1",
            [id]
          )
        end
      )

      conn
      |> with_pat(admin)
      |> put_repo_connection(project.id, @body)
      |> assert_problem(409, :concurrent_edit, [])

      refute connection_of(project)
    end
  end
end
