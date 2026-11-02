defmodule LightningWeb.API.RepoConnection.ReadingTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Mox, only: [verify_on_exit!: 1]
  import Lightning.GithubHelpers
  import LightningWeb.API.SessionHelpers
  import LightningWeb.ApiProjectsHelpers
  import LightningWeb.ApiRepoConnectionHelpers

  setup :verify_on_exit!

  setup %{conn: conn} do
    viewer = insert(:user)
    project = insert(:project, project_users: [%{user: viewer, role: :viewer}])

    repo_connection =
      insert(:project_repo_connection,
        project: project,
        repo: repo(),
        branch: "somebranch",
        github_installation_id: installation_id()
      )

    {:ok,
     conn: put_req_header(conn, "accept", "application/json"),
     viewer: viewer,
     project: project,
     repo_connection: repo_connection}
  end

  defp body(repo_connection, verified, problems) do
    self =
      "#{LightningWeb.Endpoint.url()}/api/projects/#{repo_connection.project_id}/repo_connection"

    %{
      "data" => %{
        "type" => "repo_connections",
        "id" => repo_connection.id,
        "attributes" => %{
          "repo" => repo(),
          "branch" => "somebranch",
          "github_installation_id" => installation_id(),
          "config_path" => "./openfn-#{repo_connection.project_id}-config.json",
          "verified" => verified,
          "problems" => problems,
          "inserted_at" => DateTime.to_iso8601(repo_connection.inserted_at),
          "updated_at" => DateTime.to_iso8601(repo_connection.updated_at)
        },
        "relationships" => %{},
        "links" => %{"self" => self}
      },
      "links" => %{"self" => self}
    }
  end

  # The checks in the order Lightning asks GitHub, each present or not.
  defp expect_checks(project_id, present) do
    expect_create_installation_token(installation_id())
    expect_get_repo(repo())

    for {path, present?} <- [
          {".github/workflows/openfn-pull.yml", present[:pull]},
          {".github/workflows/openfn-#{project_id}-deploy.yml",
           present[:deploy]},
          {"openfn-#{project_id}-config.json", present[:config]}
        ] do
      expect_get_repo_content(repo(), path, if(present?, do: 200, else: 404))
    end

    expect_create_repo_secret(
      repo(),
      api_secret_name(project_id),
      if(present[:secret], do: 200, else: 404)
    )
  end

  describe "reading a project's repo connection" do
    test "a viewer reads it on a session token, verified when everything is in the repo",
         %{conn: conn, viewer: viewer, project: project} = ctx do
      expect_checks(project.id,
        pull: true,
        deploy: true,
        config: true,
        secret: true
      )

      conn =
        conn
        |> session_conn(viewer)
        |> get(~p"/api/projects/#{project.id}/repo_connection")

      assert json_response(conn, 200) == body(ctx.repo_connection, true, [])
    end

    test "lists every part missing from the repo, not just the first",
         %{conn: conn, viewer: viewer, project: project} = ctx do
      expect_checks(project.id,
        pull: true,
        deploy: false,
        config: true,
        secret: false
      )

      conn =
        conn
        |> with_pat(viewer)
        |> get(~p"/api/projects/#{project.id}/repo_connection")

      assert json_response(conn, 200) ==
               body(ctx.repo_connection, false, [
                 "missing_deploy_yml",
                 "missing_api_secret"
               ])
    end

    test "a GitHub Lightning can't reach doesn't fail the request",
         %{conn: conn, viewer: viewer, project: project} = ctx do
      Mox.expect(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:error, :econnrefused}
      end)

      conn =
        conn
        |> with_pat(viewer)
        |> get(~p"/api/projects/#{project.id}/repo_connection")

      assert json_response(conn, 200) ==
               body(ctx.repo_connection, false, ["github_unavailable"])
    end
  end
end
