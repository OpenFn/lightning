defmodule LightningWeb.API.RepoConnection.SyncingTest do
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

  setup :verify_on_exit!

  setup %{conn: conn} do
    editor = insert(:user, email: "editor@example.com")
    project = insert(:project, project_users: [%{user: editor, role: :editor}])

    insert(:project_repo_connection,
      project: project,
      repo: repo(),
      branch: "somebranch",
      github_installation_id: installation_id()
    )

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     editor: editor,
     project: project}
  end

  # The pull workflow's dispatch, handing its commit message to the test.
  defp expect_dispatch(test_pid) do
    expect_create_installation_token(installation_id())
    expect_get_repo(repo())

    Mox.expect(Lightning.Tesla.Mock, :call, fn %{url: url, body: body}, _opts ->
      assert url =~ "/actions/workflows/openfn-pull.yml/dispatches"

      send(
        test_pid,
        {:commit_message, Jason.decode!(body)["inputs"]["commitMessage"]}
      )

      {:ok, %Tesla.Env{status: 204, body: ""}}
    end)
  end

  describe "syncing to GitHub" do
    test "an editor starts a sync on a session token with their message, answering 202 with no body",
         %{conn: conn, editor: editor, project: project} do
      expect_dispatch(self())

      conn =
        conn
        |> session_conn(editor)
        |> sync_repo_connection(project.id, %{"commit_message" => "nightly"})

      assert response(conn, 202) == ""
      assert_received {:commit_message, "nightly"}
    end

    test "without a message, the commit names the caller",
         %{conn: conn, editor: editor, project: project} do
      expect_dispatch(self())

      conn
      |> with_pat(editor)
      |> sync_repo_connection(project.id)
      |> response(202)

      assert_received {:commit_message,
                       "user editor@example.com initiated a sync from Lightning"}
    end

    test "a body it can't use answers 422, and nothing is started",
         %{conn: conn, editor: editor, project: project} do
      conn
      |> with_pat(editor)
      |> sync_repo_connection(project.id, %{
        "commit_message" => 7,
        "branch" => "x"
      })
      |> assert_problem(422, :invalid, [
        %{
          "pointer" => "#/branch",
          "code" => "unknown_key",
          "detail" => "is not accepted"
        },
        %{
          "pointer" => "#/commit_message",
          "code" => "type",
          "detail" => "is invalid"
        }
      ])
    end

    test "a project with no connection answers 404", %{
      conn: conn,
      editor: editor
    } do
      project = insert(:project, project_users: [%{user: editor, role: :owner}])

      conn
      |> with_pat(editor)
      |> sync_repo_connection(project.id)
      |> assert_problem(404, :not_found, [])
    end

    test "a plan without GitHub sync answers 402", %{
      conn: conn,
      editor: editor,
      project: project
    } do
      for reason <- [:github_sync_not_allowed, :exceeds_limit] do
        Mox.stub(MockUsageLimiter, :limit_action, fn
          %{type: :github_sync}, _context ->
            {:error, reason, %Message{text: "No"}}

          _action, _context ->
            :ok
        end)

        conn
        |> with_pat(editor)
        |> sync_repo_connection(project.id)
        |> assert_problem(402, :exceeds_limit, [])
      end
    end

    test "GitHub refusing the dispatch answers 503", %{
      conn: conn,
      editor: editor,
      project: project
    } do
      expect_create_installation_token(installation_id())
      expect_get_repo(repo())

      expect_create_workflow_dispatch(repo(), "openfn-pull.yml",
        resp_status: 422,
        resp_body: %{"message" => "Unexpected inputs"}
      )

      conn
      |> with_pat(editor)
      |> sync_repo_connection(project.id)
      |> assert_problem(503, :service_unavailable, [])
    end
  end
end
