defmodule LightningWeb.API.ScopeTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  alias Lightning.Accounts
  alias Lightning.ServiceAccount.AccessToken

  setup %{conn: conn} do
    {account, _private_key} = service_account_with_key()
    Mox.stub(Lightning.MockConfig, :service_account, fn -> account end)

    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :owner}])
    workflow = insert(:simple_workflow, project: project)

    workorder =
      insert(:workorder, dataclip: insert(:dataclip), workflow: workflow)

    run =
      insert(:run,
        work_order: workorder,
        dataclip: workorder.dataclip,
        starting_trigger: hd(workflow.triggers)
      )

    conn =
      conn
      |> put_req_header("accept", "application/json")
      |> put_req_header("content-type", "application/json")

    %{
      conn: conn,
      account: account,
      user: user,
      project: project,
      workflow: workflow,
      job: hd(workflow.jobs),
      workorder: workorder,
      run: run,
      repo_connection: insert(:project_repo_connection, project: project)
    }
  end

  describe "a token without the grant a route needs" do
    test "projects:write is needed for projects, provisioning, workflows, jobs, runs, work orders and log lines",
         ctx do
      %{project: project, workflow: workflow, job: job} = ctx
      missing = Ecto.UUID.generate()
      new_project_id = Ecto.UUID.generate()
      repo_connection = bearer(ctx.conn, ctx.repo_connection.access_token)
      short_account = bearer(ctx.conn, issue(ctx, ["users:write"]))

      repo_connection_answers =
        for path <- [
              ~p"/api/projects",
              ~p"/api/projects/#{project.id}",
              ~p"/api/projects/#{missing}",
              ~p"/api/jobs",
              ~p"/api/jobs?#{%{project_id: project.id}}",
              ~p"/api/jobs?#{%{project_id: missing}}",
              ~p"/api/projects/#{project.id}/jobs",
              ~p"/api/projects/#{missing}/jobs",
              ~p"/api/jobs/#{job.id}",
              ~p"/api/jobs/#{missing}",
              ~p"/api/runs",
              ~p"/api/runs?state=sideways",
              ~p"/api/projects/#{project.id}/runs",
              ~p"/api/projects/#{missing}/runs?state=sideways",
              ~p"/api/runs/#{ctx.run.id}",
              ~p"/api/runs/#{missing}",
              ~p"/api/work_orders",
              ~p"/api/work_orders?state=sideways",
              ~p"/api/projects/#{project.id}/work_orders",
              ~p"/api/projects/#{missing}/work_orders?state=sideways",
              ~p"/api/work_orders/#{ctx.workorder.id}",
              ~p"/api/work_orders/#{missing}",
              ~p"/api/log_lines",
              ~p"/api/log_lines?#{%{project_id: project.id}}",
              ~p"/api/log_lines?#{%{project_id: missing}}",
              ~p"/api/log_lines?level=loud&run_id=run-ish",
              ~p"/api/workflows/#{workflow.id}",
              ~p"/api/workflows/#{missing}"
            ] do
          get(repo_connection, path)
        end

      assert_refused_for_scope(repo_connection_answers, "projects:write")

      # Each of these is refused before its body is read, so a body that would
      # fail on its own does not change the answer.
      assert_refused_for_scope(
        [
          put(repo_connection, ~p"/api/projects/#{missing}", ~s({"name": "x"})),
          post(
            repo_connection,
            ~p"/api/projects/#{project.id}/workflows",
            "[1]"
          ),
          patch(
            repo_connection,
            ~p"/api/projects/#{project.id}/workflows/#{workflow.id}",
            ~s({"name": ""})
          ),
          post(
            repo_connection,
            ~p"/api/provision",
            ~s({"id": "#{new_project_id}"})
          )
        ],
        "projects:write"
      )

      refute Lightning.Repo.get(Lightning.Projects.Project, new_project_id)
      refute Lightning.Repo.get(Lightning.Projects.Project, missing)

      assert_refused_for_scope(
        [
          get(short_account, ~p"/api/projects/#{project.id}"),
          get(short_account, ~p"/api/projects/#{missing}"),
          put(short_account, ~p"/api/projects/#{project.id}", ~s({"name": "x"})),
          put(short_account, ~p"/api/projects/#{missing}", ~s({"name": "x"}))
        ],
        "projects:write"
      )

      refute Lightning.Repo.get(Lightning.Projects.Project, missing)
    end

    test "collections:write is needed to read or write a collection through the API",
         %{project: project} = ctx do
      collection = insert(:collection, project: project)
      missing = Ecto.UUID.generate()

      for caller <- [
            bearer(ctx.conn, ctx.repo_connection.access_token),
            bearer(ctx.conn, issue(ctx, ["projects:write"]))
          ] do
        assert_refused_for_scope(
          [
            get(
              caller,
              ~p"/api/projects/#{project.id}/collections/#{collection.id}"
            ),
            get(caller, ~p"/api/projects/#{project.id}/collections/#{missing}"),
            put(
              caller,
              ~p"/api/projects/#{project.id}/collections/#{missing}",
              ~s({"name": "patients"})
            )
          ],
          "collections:write"
        )
      end

      refute Lightning.Repo.get(Lightning.Collections.Collection, missing)
    end

    test "credentials:write is needed to list, read, create, replace or delete a credential",
         ctx do
      credential = insert(:credential, user: ctx.user)
      missing = Ecto.UUID.generate()
      repo_connection = bearer(ctx.conn, ctx.repo_connection.access_token)
      short_account = bearer(ctx.conn, issue(ctx, ["projects:write"]))

      assert_refused_for_scope(
        [
          get(repo_connection, ~p"/api/credentials"),
          get(repo_connection, ~p"/api/projects/#{ctx.project.id}/credentials"),
          get(repo_connection, ~p"/api/projects/#{missing}/credentials"),
          post(
            repo_connection,
            ~p"/api/credentials",
            Jason.encode!(%{
              "name" => "Planted",
              "schema" => "raw",
              "credential_bodies" => [
                %{"name" => "main", "body" => %{"a" => "b"}}
              ]
            })
          ),
          delete(repo_connection, ~p"/api/credentials/#{credential.id}"),
          delete(repo_connection, ~p"/api/credentials/#{missing}")
        ],
        "credentials:write"
      )

      refute Lightning.Repo.get_by(Lightning.Credentials.Credential,
               name: "Planted"
             )

      assert Lightning.Repo.get(Lightning.Credentials.Credential, credential.id)

      for caller <- [repo_connection, short_account] do
        assert_refused_for_scope(
          [
            get(caller, ~p"/api/credentials/#{credential.id}"),
            get(caller, ~p"/api/credentials/#{missing}"),
            put(caller, ~p"/api/credentials/#{missing}", ~s({"name": "x"}))
          ],
          "credentials:write"
        )
      end

      refute Lightning.Repo.get(Lightning.Credentials.Credential, missing)
    end

    test "users:read is needed to list or show users", ctx do
      short_account = bearer(ctx.conn, issue(ctx, ["users:write"]))

      assert_refused_for_scope(
        [
          get(short_account, ~p"/api/users?email=a@example.com"),
          get(short_account, ~p"/api/users/#{insert(:user).id}"),
          get(short_account, ~p"/api/users/#{Ecto.UUID.generate()}")
        ],
        "users:read"
      )
    end

    test "users:write is needed to create or change a user", ctx do
      short_account = bearer(ctx.conn, issue(ctx, ["users:read"]))
      user = insert(:user, first_name: "Ada")

      assert_refused_for_scope(
        [
          post(
            short_account,
            ~p"/api/users",
            Jason.encode!(%{
              email: "no@example.com",
              password: "a long enough password"
            })
          ),
          post(short_account, ~p"/api/users", "[1]"),
          patch(
            short_account,
            ~p"/api/users/#{user.id}",
            ~s({"first_name": "Grace"})
          ),
          patch(
            short_account,
            ~p"/api/users/#{Ecto.UUID.generate()}",
            ~s({"first_name": "Grace"})
          )
        ],
        "users:write"
      )

      refute Accounts.get_user_by_email("no@example.com")
      assert %{first_name: "Ada"} = Accounts.get_user(user.id)
    end
  end

  defp issue(%{account: account}, grants), do: AccessToken.issue(account, grants)

  defp bearer(conn, token),
    do: put_req_header(conn, "authorization", "Bearer " <> token)
end
