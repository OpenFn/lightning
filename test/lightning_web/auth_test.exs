defmodule LightningWeb.AuthTest do
  @moduledoc """
  One route per JSON pipeline, refused for no token, for a bad one and for a
  `Bearer` header it can't read, which token kinds each pipeline takes (the
  session token among them), and the routes open only to people or only to a
  session token, a
  locked-out account on a bearer pipeline, and the bearer scheme read without
  regard to case on one route per auth plug. Then the checks of a request
  against webhook auth methods.
  """
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers
  import Plug.Test, only: [conn: 2]

  alias Lightning.Accounts
  alias Lightning.Config.API, as: ConfigAPI
  alias Lightning.Repo
  alias Lightning.ServiceAccount.AccessToken
  alias Lightning.Workflows.WebhookAuthMethod
  alias LightningWeb.Auth

  @invalid_token [~s(Bearer error="invalid_token")]
  @expired_token [
    ~s(Bearer error="invalid_token", error_description="The access token expired")
  ]

  setup %{conn: conn} do
    {account, _private_key} = service_account_with_key()
    Mox.stub(Lightning.MockConfig, :service_account, fn -> account end)

    %{conn: put_req_header(conn, "accept", "application/json"), account: account}
  end

  describe "a lower-case bearer scheme" do
    test "authenticates a service account's access token on GET /api/users",
         %{conn: conn, account: account} do
      conn =
        conn
        |> put_req_header(
          "authorization",
          "bearer " <> AccessToken.issue(account, ["users:read"])
        )
        |> get(~p"/api/users")

      assert %{"data" => _users} = json_response(conn, 200)
    end

    test "authenticates a personal access token on GET /api/projects",
         %{conn: conn} do
      project = insert(:project, project_users: [%{user: user = insert(:user)}])

      conn =
        conn
        |> put_req_header(
          "authorization",
          "bearer " <> Accounts.generate_api_token(user)
        )
        |> get(~p"/api/projects")

      assert %{"data" => [%{"id" => id}]} = json_response(conn, 200)
      assert id == project.id
    end

    test "authenticates a personal access token on GET /collections/:name",
         %{conn: conn} do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])
      collection = insert(:collection, project: project)

      conn =
        conn
        |> put_req_header(
          "authorization",
          "bearer " <> Accounts.generate_api_token(user)
        )
        |> get(~p"/collections/#{collection.name}")

      assert %{"items" => [], "cursor" => nil} = json_response(conn, 200)
    end
  end

  for {pipeline, path} <- [
        person_or_service_account_api:
          "/api/projects/7b0c1b4c-0c62-4b8e-9a39-0a6c9e1f2d11",
        authenticated_api: "/collections/a-collection"
      ] do
    describe "the #{pipeline} pipeline, GET #{path}" do
      test "answers no token with unauthenticated and a bare Bearer challenge",
           %{conn: conn} do
        conn = get(conn, unquote(path))

        assert_unauthenticated(conn, :unauthenticated, ["Bearer"])
      end

      test "answers a bad token with invalid_token", %{conn: conn} do
        conn =
          conn
          |> put_req_header("authorization", "Bearer not-a-token")
          |> get(unquote(path))

        assert_unauthenticated(conn, :invalid_token, @invalid_token)
      end

      test "answers another scheme as no token sent", %{conn: conn} do
        conn =
          conn
          |> put_req_header("authorization", "Basic dXNlcjpwYXNz")
          |> get(unquote(path))

        assert_unauthenticated(conn, :unauthenticated, ["Bearer"])
      end
    end

    describe "the #{pipeline} pipeline, GET #{path}, a Bearer header Lightning can't read" do
      test "answers no token after the scheme with invalid_request",
           %{conn: conn} do
        conn =
          conn
          |> put_req_header("authorization", "Bearer")
          |> get(unquote(path))

        assert_invalid_request(conn)
      end

      test "answers whitespace inside the token with invalid_request",
           %{conn: conn} do
        conn =
          conn
          |> put_req_header("authorization", "Bearer a b")
          |> get(unquote(path))

        assert_invalid_request(conn)
      end

      test "answers two Bearer headers with invalid_request", %{conn: conn} do
        # Cowboy joins a repeated request header into one value with ", ".
        conn =
          conn
          |> put_req_header("authorization", "Bearer x, Bearer x")
          |> get(unquote(path))

        assert_invalid_request(conn)
      end
    end
  end

  for path <- [
        "/api/ai_assistant/sessions",
        "/adaptors/catalogue"
      ] do
    describe "the authenticated_json pipeline, GET #{path}" do
      test "answers no session with unauthenticated and the Session challenge",
           %{conn: conn} do
        conn = get(conn, unquote(path))

        assert_session_refused(conn)
      end

      test "answers a bearer token with unauthenticated, since it takes only the cookie",
           %{conn: conn} do
        conn =
          conn
          |> put_req_header("authorization", "Bearer not-a-token")
          |> get(unquote(path))

        assert_session_refused(conn)
      end
    end
  end

  # Proves the plug is wired into the /api scope, rather than only that the
  # plug function itself refuses — see user_auth_test.exs for the unit tests.
  describe "with an account past its confirmation deadline" do
    test "gets a 401, and the same token works again once confirmed", %{
      conn: conn
    } do
      Mox.stub(Lightning.MockConfig, :check_flag?, fn
        :require_email_verification -> true
        flag -> ConfigAPI.check_flag?(flag)
      end)

      user = insert(:user)
      insert(:project, project_users: [%{user: user}])

      token = Lightning.Accounts.generate_api_token(user)

      user =
        user
        |> Ecto.Changeset.change(
          confirmed_at: nil,
          inserted_at:
            DateTime.utc_now()
            |> DateTime.add(-50, :hour)
            |> DateTime.truncate(:second)
        )
        |> Repo.update!()

      refused = conn |> assign_bearer(token) |> get(~p"/api/projects")

      assert_problem(refused, 401, :invalid_token, [])

      user
      |> Ecto.Changeset.change(
        confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )
      |> Repo.update!()

      allowed = conn |> assign_bearer(token) |> get(~p"/api/projects")

      assert [%{"type" => "projects"}] = json_response(allowed, 200)["data"]
    end

    test "gets a 401 on GET /collections/:name too, and the same token works again once confirmed",
         %{conn: conn} do
      Mox.stub(Lightning.MockConfig, :check_flag?, fn
        :require_email_verification -> true
        flag -> ConfigAPI.check_flag?(flag)
      end)

      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])
      collection = insert(:collection, project: project)
      token = Accounts.generate_api_token(user)

      user =
        user
        |> Ecto.Changeset.change(
          confirmed_at: nil,
          inserted_at:
            DateTime.utc_now()
            |> DateTime.add(-50, :hour)
            |> DateTime.truncate(:second)
        )
        |> Repo.update!()

      path = ~p"/collections/#{collection.name}"
      authorization = "Bearer " <> token

      refused =
        conn |> put_req_header("authorization", authorization) |> get(path)

      assert_unauthenticated(refused, :invalid_token, @invalid_token)

      user
      |> Ecto.Changeset.change(
        confirmed_at: DateTime.utc_now() |> DateTime.truncate(:second)
      )
      |> Repo.update!()

      allowed =
        conn |> put_req_header("authorization", authorization) |> get(path)

      assert %{"items" => []} = json_response(allowed, 200)
    end
  end

  describe "a token of the wrong kind" do
    setup %{account: account} do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user, role: :owner}])
      collection = insert(:collection, project: project)
      workflow = insert(:simple_workflow, project: project)

      workorder =
        insert(:workorder, dataclip: insert(:dataclip), workflow: workflow)

      run =
        insert(:run,
          work_order: workorder,
          dataclip: workorder.dataclip,
          starting_trigger: hd(workflow.triggers)
        )

      %{
        project: project,
        collection: collection,
        tokens: [
          service_account: AccessToken.issue(account, AccessToken.scopes()),
          expired_service_account:
            expired_access_token(account, "users:read projects:write"),
          personal: Accounts.generate_api_token(user),
          repo_connection:
            insert(:project_repo_connection, project: project).access_token,
          run: Lightning.Workers.generate_run_token(run),
          session: {:session, user}
        ]
      }
    end

    test "/api/users takes a service account's access token, and refuses a person's with 403",
         %{conn: conn, tokens: tokens} do
      assert_each_kind(conn, tokens, ~p"/api/users",
        service_account: :logs_in,
        expired_service_account: :expired_token,
        personal: :forbidden,
        repo_connection: {:insufficient_scope, "users:read"},
        run: :invalid_token,
        session: :forbidden
      )
    end

    test "person_or_service_account_api takes a service account's or a person's token, and not a run token",
         %{conn: conn, tokens: tokens, project: project} do
      assert_each_kind(conn, tokens, ~p"/api/projects/#{project.id}",
        service_account: :logs_in,
        expired_service_account: :expired_token,
        personal: :logs_in,
        repo_connection: {:insufficient_scope, "projects:write"},
        run: :invalid_token,
        session: :logs_in
      )
    end

    # A route open only to people answers the other kinds the pipeline takes
    # with 403 forbidden: there is no scope that would let them in.
    test "GET /api/me takes a person's tokens, and refuses the service account and a repo connection with 403",
         %{conn: conn, tokens: tokens} do
      assert_each_kind(conn, tokens, ~p"/api/me",
        service_account: :forbidden,
        expired_service_account: :expired_token,
        personal: :logs_in,
        repo_connection: :forbidden,
        run: :invalid_token,
        session: :logs_in
      )
    end

    test "starting or cancelling a credential's transfer takes a person's tokens, and refuses the service account and a repo connection with 403",
         %{conn: conn, tokens: tokens} do
      {:session, user} = tokens[:session]
      credential = insert(:credential, user: user)
      path = ~p"/api/credentials/#{credential.id}/transfer"

      for {method, answered} <- [put: {422, :invalid}, delete: {404, :not_found}] do
        assert_each_kind_on(conn, tokens, {method, path},
          service_account: :forbidden,
          expired_service_account: :expired_token,
          personal: {:answers, answered},
          repo_connection: :forbidden,
          run: :invalid_token,
          session: {:answers, answered}
        )
      end

      assert Lightning.Repo.reload!(credential).transfer_status == nil
    end

    test "GET /api/projects/:project_id/sandboxes takes a person's tokens or a service account's, and not a repo connection's",
         %{conn: conn, tokens: tokens, project: project} do
      assert_each_kind(conn, tokens, ~p"/api/projects/#{project.id}/sandboxes",
        service_account: :logs_in,
        expired_service_account: :expired_token,
        personal: :logs_in,
        repo_connection: {:insufficient_scope, "projects:write"},
        run: :invalid_token,
        session: :logs_in
      )
    end

    # GitHub isn't reachable here, which the route reports in its body.
    test "GET /api/projects/:project_id/repo_connection takes a person's tokens, and refuses the service account and a repo connection with 403",
         %{conn: conn, tokens: tokens, project: project} do
      Mox.stub(Lightning.Tesla.Mock, :call, fn _env, _opts ->
        {:error, :econnrefused}
      end)

      assert_each_kind(
        conn,
        tokens,
        ~p"/api/projects/#{project.id}/repo_connection",
        service_account: :forbidden,
        expired_service_account: :expired_token,
        personal: :logs_in,
        repo_connection: :forbidden,
        run: :invalid_token,
        session: :logs_in
      )
    end

    test "GET /api/projects/:project_id/webhook_auth_methods takes a person's tokens, and refuses the service account and a repo connection with 403",
         %{conn: conn, tokens: tokens, project: project} do
      assert_each_kind(
        conn,
        tokens,
        ~p"/api/projects/#{project.id}/webhook_auth_methods",
        service_account: :forbidden,
        expired_service_account: :expired_token,
        personal: :logs_in,
        repo_connection: :forbidden,
        run: :invalid_token,
        session: :logs_in
      )
    end

    test "GET /api/projects/:project_id/channels takes a person's tokens, and refuses the service account and a repo connection with 403",
         %{conn: conn, tokens: tokens, project: project} do
      assert_each_kind(conn, tokens, ~p"/api/projects/#{project.id}/channels",
        service_account: :forbidden,
        expired_service_account: :expired_token,
        personal: :logs_in,
        repo_connection: :forbidden,
        run: :invalid_token,
        session: :logs_in
      )
    end

    test "GET /api/projects/:project_id/channel_requests takes a person's tokens, and refuses the service account and a repo connection with 403",
         %{conn: conn, tokens: tokens, project: project} do
      assert_each_kind(
        conn,
        tokens,
        ~p"/api/projects/#{project.id}/channel_requests",
        service_account: :forbidden,
        expired_service_account: :expired_token,
        personal: :logs_in,
        repo_connection: :forbidden,
        run: :invalid_token,
        session: :logs_in
      )
    end

    test "authenticated_api takes a personal or run token, and not a repo connection's or a service account's",
         %{conn: conn, tokens: tokens, collection: collection} do
      assert_each_kind(conn, tokens, ~p"/collections/#{collection.name}",
        service_account: :invalid_token,
        expired_service_account: :invalid_token,
        personal: :logs_in,
        repo_connection: :invalid_token,
        run: :logs_in,
        session: :unauthenticated
      )
    end

    test "GET /api/session takes only a session token, and reads every bearer token as none",
         %{conn: conn, tokens: tokens} do
      assert_each_kind(conn, tokens, ~p"/api/session",
        service_account: :session_refused,
        expired_service_account: :session_refused,
        personal: :session_refused,
        repo_connection: :session_refused,
        run: :session_refused,
        session: :logs_in
      )
    end

    test "a workflow's snapshots, one snapshot, its versions, and the workflow templates take a person's tokens, and refuse the service account and a repo connection with 403",
         %{conn: conn, tokens: tokens, project: project} do
      workflow = insert(:simple_workflow, project: project) |> with_snapshot()

      snapshot =
        Repo.get_by!(Lightning.Workflows.Snapshot, workflow_id: workflow.id)

      for path <- [
            ~p"/api/workflows/#{workflow.id}/snapshots",
            ~p"/api/workflows/#{workflow.id}/snapshots/#{snapshot.id}",
            ~p"/api/workflows/#{workflow.id}/versions",
            ~p"/api/workflow_templates"
          ] do
        assert_each_kind(conn, tokens, path,
          service_account: :forbidden,
          expired_service_account: :expired_token,
          personal: :logs_in,
          repo_connection: :forbidden,
          run: :invalid_token,
          session: :logs_in
        )
      end
    end

    test "GET and DELETE /api/me/tokens take a person's tokens, and refuse the service account and a repo connection with 403",
         %{conn: conn, tokens: tokens} do
      people_only = [
        service_account: :forbidden,
        expired_service_account: :expired_token,
        repo_connection: :forbidden,
        run: :invalid_token
      ]

      assert_each_kind_on(
        conn,
        tokens,
        {:get, ~p"/api/me/tokens"},
        people_only ++ [personal: :logs_in, session: :logs_in]
      )

      assert_each_kind_on(
        conn,
        tokens,
        {:delete, ~p"/api/me/tokens/#{Ecto.UUID.generate()}"},
        people_only ++ [personal: {:status, 404}, session: {:status, 404}]
      )
    end

    test "POST /api/me/tokens takes only a stepped-up session token, and refuses every bearer token with 403",
         %{conn: conn, tokens: tokens} do
      assert_each_kind_on(conn, tokens, {:post, ~p"/api/me/tokens"},
        service_account: :forbidden,
        expired_service_account: :expired_token,
        personal: :forbidden,
        repo_connection: :forbidden,
        run: :invalid_token,
        session: :step_up_required
      )
    end

    test "/api/me/mfa and the GitHub connection take only a session token, stepped up to change MFA or make backup codes, and refuse every bearer token with 403",
         %{conn: conn, tokens: tokens} do
      bearer_refused = [
        service_account: :forbidden,
        expired_service_account: :expired_token,
        personal: :forbidden,
        repo_connection: :forbidden,
        run: :invalid_token
      ]

      for {route, session} <- [
            {{:get, ~p"/api/me/mfa"}, :logs_in},
            {{:post, ~p"/api/me/mfa"}, {:status, 201}},
            {{:put, ~p"/api/me/mfa"}, :step_up_required},
            {{:delete, ~p"/api/me/mfa"}, :step_up_required},
            {{:post, ~p"/api/me/mfa/backup_codes"}, :step_up_required},
            {{:delete, ~p"/api/me/github_connection"}, {:status, 204}}
          ] do
        assert_each_kind_on(
          conn,
          tokens,
          route,
          bearer_refused ++ [session: session]
        )
      end
    end

    # The routes write, so each person's token is shown let in by the answer
    # the route gives once it reads the request: 404 for a workflow the
    # project hasn't got, 422 for a template with no name.
    test "deleting a workflow and publishing it as a template take a person's tokens, and refuse the service account and a repo connection with 403",
         %{conn: conn, tokens: tokens, project: project} do
      {:session, user} = tokens[:session]
      Repo.update!(Ecto.Changeset.change(user, support_user: true))
      workflow = insert(:simple_workflow, project: project)

      for {verb, path, let_in} <- [
            {:delete,
             ~p"/api/projects/#{project.id}/workflows/#{Ecto.UUID.generate()}",
             {404, :not_found}},
            {:put, ~p"/api/workflows/#{workflow.id}/template", {422, :invalid}}
          ],
          {kind, token} <- tokens do
        conn =
          conn
          |> with_token(token)
          |> put_req_header("content-type", "application/json")
          |> dispatch(@endpoint, verb, path, "{}")

        case kind do
          kind when kind in [:personal, :session] ->
            {status, code} = let_in
            assert_problem(conn, status, code)

          kind when kind in [:service_account, :repo_connection] ->
            assert_problem(conn, 403, :forbidden, [])

          :expired_service_account ->
            assert_unauthenticated(conn, :invalid_token, @expired_token)

          :run ->
            assert_unauthenticated(conn, :invalid_token, @invalid_token)
        end
      end

      refute Repo.reload!(workflow).deleted_at
    end

    # The tokens' person has no GitHub connection, which is 403 too, so a
    # person's tokens being let in is shown in `API.Me.GithubTest`.
    test "the GitHub lists take a person's tokens, and refuse the service account and a repo connection with 403",
         %{conn: conn, tokens: tokens} do
      for route <- [
            {:get, ~p"/api/me/github_repos"},
            {:get, ~p"/api/me/github_repos/openfn/lightning/branches"}
          ] do
        assert_each_kind_on(conn, tokens, route,
          service_account: :forbidden,
          expired_service_account: :expired_token,
          personal: :forbidden,
          repo_connection: :forbidden,
          run: :invalid_token,
          session: :forbidden
        )
      end
    end

    # The tokens' person isn't a superuser, so their tokens are refused too.
    test "/api/auth_provider refuses the service account and a repo connection with 403",
         %{conn: conn, tokens: tokens} do
      for method <- [:get, :put, :delete] do
        assert_each_kind_on(conn, tokens, {method, ~p"/api/auth_provider"},
          service_account: :forbidden,
          expired_service_account: :expired_token,
          personal: :forbidden,
          repo_connection: :forbidden,
          run: :invalid_token,
          session: :forbidden
        )
      end
    end

    test "GET /api/projects/:project_id/members takes a service account's or a person's token",
         %{conn: conn, tokens: tokens, project: project} do
      assert_each_kind(conn, tokens, ~p"/api/projects/#{project.id}/members",
        service_account: :logs_in,
        expired_service_account: :expired_token,
        personal: :logs_in,
        repo_connection: {:insufficient_scope, "projects:write"},
        run: :invalid_token,
        session: :logs_in
      )
    end

    test "PUT /api/projects/:project_id/members/:user_id/notifications takes a person's tokens, refuses the service account with 403 and a repo connection for its grant",
         %{conn: conn, tokens: tokens, project: project} do
      {:session, user} = tokens[:session]

      assert_each_kind_writing(
        conn,
        tokens,
        ~p"/api/projects/#{project.id}/members/#{user.id}/notifications",
        %{"failure_alert" => true, "digest" => "daily"},
        service_account: :forbidden,
        expired_service_account: :expired_token,
        personal: :logs_in,
        repo_connection: {:insufficient_scope, "projects:write"},
        run: :invalid_token,
        session: :logs_in
      )
    end

    test "POST /api/projects/:project_id/invitations takes a person's tokens, refuses the service account with 403 and a repo connection for its grant",
         %{conn: conn, tokens: tokens, project: project} do
      assert_each_kind_posting(
        conn,
        tokens,
        ~p"/api/projects/#{project.id}/invitations",
        &%{
          "email" => "invited.#{&1}@example.com",
          "first_name" => "Invited",
          "last_name" => "Person",
          "role" => "editor"
        },
        service_account: :forbidden,
        expired_service_account: :expired_token,
        personal: :logs_in,
        repo_connection: {:insufficient_scope, "projects:write"},
        run: :invalid_token,
        session: :logs_in
      )
    end

    test "the AI assistant takes only a session token, and refuses every other kind the pipeline takes with 403",
         %{conn: conn, tokens: tokens, project: project} do
      {:session, user} = tokens[:session]

      session =
        insert(:chat_session,
          session_type: "workflow_template",
          project: project,
          user: user
        )

      for path <- [
            ~p"/api/projects/#{project.id}/ai_sessions?#{%{workflow_id: Ecto.UUID.generate()}}",
            ~p"/api/ai_sessions/#{session.id}"
          ] do
        assert_each_kind(conn, tokens, path,
          service_account: :forbidden,
          expired_service_account: :expired_token,
          personal: :forbidden,
          repo_connection: :forbidden,
          run: :invalid_token,
          session: :logs_in
        )
      end

      Process.put(:oban_testing, :manual)

      failed =
        insert(:chat_message,
          chat_session: session,
          user: user,
          role: :user,
          status: :error
        )

      for {path, body} <- [
            {~p"/api/projects/#{project.id}/ai_sessions",
             %{"kind" => "workflow", "message" => %{"content" => "Hi"}}},
            {~p"/api/ai_sessions/#{session.id}/messages", %{"content" => "Hi"}},
            {~p"/api/ai_sessions/#{session.id}/messages/#{failed.id}/retries",
             %{}}
          ] do
        assert_each_kind_posting_ai(conn, tokens, path, body,
          service_account: :forbidden,
          expired_service_account: :expired_token,
          personal: :forbidden,
          repo_connection: :forbidden,
          run: :invalid_token,
          session: {:status, 201}
        )
      end
    end

    test "GET /api/oauth_clients takes a person's tokens, and refuses the service account, which owns no client, with 403",
         %{conn: conn, tokens: tokens} do
      assert_each_kind(conn, tokens, ~p"/api/oauth_clients",
        service_account: :forbidden,
        expired_service_account: :expired_token,
        personal: :logs_in,
        repo_connection: {:insufficient_scope, "credentials:write"},
        run: :invalid_token,
        session: :logs_in
      )
    end

    test "a project's keychain credentials and OAuth clients take a member's tokens and the service account's",
         %{conn: conn, tokens: tokens, project: project} do
      for path <- [
            ~p"/api/projects/#{project.id}/keychain_credentials",
            ~p"/api/projects/#{project.id}/oauth_clients"
          ] do
        assert_each_kind(conn, tokens, path,
          service_account: :logs_in,
          expired_service_account: :expired_token,
          personal: :logs_in,
          repo_connection: {:insufficient_scope, "credentials:write"},
          run: :invalid_token,
          session: :logs_in
        )
      end
    end

    test "a project's collections take an owner's tokens, and every collection only the service account's or a superuser's",
         %{conn: conn, tokens: tokens, project: project} do
      assert_each_kind(conn, tokens, ~p"/api/projects/#{project.id}/collections",
        service_account: :logs_in,
        expired_service_account: :expired_token,
        personal: :logs_in,
        repo_connection: {:insufficient_scope, "collections:write"},
        run: :invalid_token,
        session: :logs_in
      )

      assert_each_kind(conn, tokens, ~p"/api/collections",
        service_account: :logs_in,
        expired_service_account: :expired_token,
        personal: :forbidden,
        repo_connection: {:insufficient_scope, "collections:write"},
        run: :invalid_token,
        session: :forbidden
      )
    end

    test "scheduling a user's deletion and cancelling it take only the service account's token, and refuse a person's with 403",
         %{conn: conn, tokens: tokens} do
      unscheduled = insert(:user)
      scheduled = insert(:user, scheduled_deletion: DateTime.utc_now())

      for path <- [
            ~p"/api/users/#{unscheduled.id}",
            ~p"/api/users/#{scheduled.id}/scheduled_deletion"
          ] do
        assert_each_kind_deleting(conn, tokens, path,
          service_account: :logs_in,
          expired_service_account: :expired_token,
          personal: :forbidden,
          repo_connection: {:insufficient_scope, "users:write"},
          run: :invalid_token,
          session: :forbidden
        )
      end
    end

    test "authenticated_json takes no bearer token of any kind", %{
      conn: conn,
      tokens: tokens
    } do
      for {_kind, token} <- tokens, is_binary(token) do
        conn =
          conn
          |> put_req_header("authorization", "Bearer " <> token)
          |> get(~p"/api/ai_assistant/sessions")

        assert_session_refused(conn)
      end
    end

    test "a run's steps take a person's tokens, and refuse the service account and a repo connection with 403",
         %{conn: conn, tokens: tokens, project: project} do
      run = insert_history_run(project)

      assert_each_kind(conn, tokens, ~p"/api/runs/#{run.id}/steps",
        service_account: :forbidden,
        expired_service_account: :expired_token,
        personal: :logs_in,
        repo_connection: :forbidden,
        run: :invalid_token,
        session: :logs_in
      )
    end

    test "a project's history exports take a person's tokens, and refuse the service account and a repo connection with 403",
         %{conn: conn, tokens: tokens, project: project} do
      assert_each_kind(
        conn,
        tokens,
        ~p"/api/projects/#{project.id}/history_exports",
        service_account: :forbidden,
        expired_service_account: :expired_token,
        personal: :logs_in,
        repo_connection: :forbidden,
        run: :invalid_token,
        session: :logs_in
      )
    end

    test "one history export and its download take a person's tokens, and refuse the service account and a repo connection with 403",
         %{conn: conn, tokens: tokens, project: project} do
      export =
        insert(:project_file,
          project: project,
          status: :completed,
          path: LightningWeb.API.HistoryHelpers.stored_export_zip()
        )

      base = ~p"/api/projects/#{project.id}/history_exports/#{export.id}"

      for path <- [base, base <> "/download"] do
        assert_each_kind(conn, tokens, path,
          service_account: :forbidden,
          expired_service_account: :expired_token,
          personal: :logs_in,
          repo_connection: :forbidden,
          run: :invalid_token,
          session: :logs_in
        )
      end
    end

    # Each request is built afresh for each kind, on records of its own, so
    # one kind's write doesn't change what the next is answered.
    test "starting, retrying and cancelling runs and work orders, and exporting history, take a person's tokens, and refuse the service account and a repo connection with 403",
         %{conn: conn, tokens: tokens, project: project} do
      for request <- history_writes(project) do
        assert_each_kind_acting_on_history(conn, tokens, request,
          service_account: :forbidden,
          expired_service_account: :expired_token,
          personal: :logs_in,
          repo_connection: :forbidden,
          run: :invalid_token,
          session: :logs_in
        )
      end
    end

    test "GET /api/dataclips/:id takes a person's tokens, and refuses the service account and a repo connection with 403",
         %{conn: conn, tokens: tokens, project: project} do
      dataclip = insert(:dataclip, project: project)

      assert_each_kind(conn, tokens, ~p"/api/dataclips/#{dataclip.id}",
        service_account: :forbidden,
        expired_service_account: :expired_token,
        personal: :logs_in,
        repo_connection: :forbidden,
        run: :invalid_token,
        session: :logs_in
      )
    end

    test "GET /api/audit_events takes the service account's token with audit:read, and refuses a person who isn't a superuser with 403",
         %{conn: conn, tokens: tokens} do
      assert_each_kind(conn, tokens, ~p"/api/audit_events",
        service_account: :logs_in,
        expired_service_account: :expired_token,
        personal: :forbidden,
        repo_connection: {:insufficient_scope, "audit:read"},
        run: :invalid_token,
        session: :forbidden
      )
    end

    test "PATCH /api/dataclips/:id takes a person's tokens, and refuses the service account and a repo connection with 403",
         %{conn: conn, tokens: tokens, project: project} do
      dataclip = insert(:dataclip, project: project)

      rename = fn conn ->
        patch(conn, ~p"/api/dataclips/#{dataclip.id}", %{name: "sample"})
      end

      assert_each_kind(conn, tokens, rename,
        service_account: :forbidden,
        expired_service_account: :expired_token,
        personal: :logs_in,
        repo_connection: :forbidden,
        run: :invalid_token,
        session: :logs_in
      )
    end
  end

  defp insert_history_run(project) do
    workflow = insert(:simple_workflow, project: project)

    work_order =
      insert(:workorder, dataclip: insert(:dataclip), workflow: workflow)

    insert(:run,
      work_order: work_order,
      dataclip: work_order.dataclip,
      starting_trigger: hd(workflow.triggers)
    )
  end

  defp assert_each_kind(conn, tokens, path, expected) do
    assert Enum.sort(Keyword.keys(expected)) == Enum.sort(Keyword.keys(tokens))

    for {kind, answer} <- expected do
      conn = conn |> with_token(tokens[kind]) |> request(path)

      case answer do
        :logs_in ->
          assert conn.status == 200, "#{kind} was answered #{conn.status}"

        :unauthenticated ->
          assert_unauthenticated(conn, :unauthenticated, ["Bearer"])

        :session_refused ->
          assert_session_refused(conn)

        :invalid_token ->
          assert_unauthenticated(conn, :invalid_token, @invalid_token)

        :expired_token ->
          assert_unauthenticated(conn, :invalid_token, @expired_token)

        :forbidden ->
          assert_problem(conn, 403, :forbidden, [])
          assert get_resp_header(conn, "www-authenticate") == []

        {:insufficient_scope, grant} ->
          assert_refused_for_scope(conn, grant)
      end
    end
  end

  # As assert_each_kind/4, for any method, with an empty JSON body. A route
  # that answers a person without refusing them, such as a 404 for an id they
  # hold no token under, is written `{:status, status}`; `{:answers, {status,
  # code}}` is the problem a route that writes gives once the token kind is let
  # in.
  defp assert_each_kind_on(conn, tokens, {method, path}, expected) do
    assert Enum.sort(Keyword.keys(expected)) == Enum.sort(Keyword.keys(tokens))

    for {kind, answer} <- expected do
      conn =
        conn
        |> with_token(tokens[kind])
        |> put_req_header("content-type", "application/json")
        |> dispatch(@endpoint, method, path, "{}")

      case answer do
        :logs_in ->
          assert conn.status == 200, "#{kind} was answered #{conn.status}"

        {:status, status} ->
          assert conn.status == status, "#{kind} was answered #{conn.status}"

        {:answers, {status, code}} ->
          assert_problem(conn, status, code)

        :invalid_token ->
          assert_unauthenticated(conn, :invalid_token, @invalid_token)

        :expired_token ->
          assert_unauthenticated(conn, :invalid_token, @expired_token)

        :forbidden ->
          assert_problem(conn, 403, :forbidden, [])
          assert get_resp_header(conn, "www-authenticate") == []

        :step_up_required ->
          assert_problem(conn, 403, :step_up_required, [])
      end
    end
  end

  # As assert_each_kind/4, for a PUT of `body`.
  defp assert_each_kind_writing(conn, tokens, path, body, expected) do
    assert Enum.sort(Keyword.keys(expected)) == Enum.sort(Keyword.keys(tokens))

    for {kind, answer} <- expected do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> with_token(tokens[kind])
        |> put(path, Jason.encode!(body))

      case answer do
        :logs_in ->
          assert conn.status == 200, "#{kind} was answered #{conn.status}"

        :invalid_token ->
          assert_unauthenticated(conn, :invalid_token, @invalid_token)

        :expired_token ->
          assert_unauthenticated(conn, :invalid_token, @expired_token)

        :forbidden ->
          assert_problem(conn, 403, :forbidden, [])
          assert get_resp_header(conn, "www-authenticate") == []

        {:insufficient_scope, grant} ->
          assert_refused_for_scope(conn, grant)
      end
    end
  end

  # As assert_each_kind_writing/5, for a POST that creates, of the body
  # `body_for` gives each kind.
  defp assert_each_kind_posting(conn, tokens, path, body_for, expected) do
    assert Enum.sort(Keyword.keys(expected)) == Enum.sort(Keyword.keys(tokens))

    for {kind, answer} <- expected do
      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> with_token(tokens[kind])
        |> post(path, Jason.encode!(body_for.(kind)))

      case answer do
        :logs_in ->
          assert conn.status == 201, "#{kind} was answered #{conn.status}"

        :invalid_token ->
          assert_unauthenticated(conn, :invalid_token, @invalid_token)

        :expired_token ->
          assert_unauthenticated(conn, :invalid_token, @expired_token)

        :forbidden ->
          assert_problem(conn, 403, :forbidden, [])
          assert get_resp_header(conn, "www-authenticate") == []

        {:insufficient_scope, grant} ->
          assert_refused_for_scope(conn, grant)
      end
    end
  end

  # Each write route of a project's history: a function that builds the
  # records a request needs and answers its method, path, a body the route
  # accepts, and the status it succeeds with.
  defp history_writes(project) do
    alias LightningWeb.API.HistoryHelpers

    graph = fn -> HistoryHelpers.runnable_workflow(project) end
    pending = fn -> HistoryHelpers.pending_work_order(graph.()) end
    ran = fn -> HistoryHelpers.ran_work_order(graph.()) end

    [
      fn ->
        run = hd(pending.().runs)
        {:patch, ~p"/api/runs/#{run.id}", %{state: "cancelled"}, 200}
      end,
      fn ->
        %{run: run, step_a: step} = ran.()
        {:post, ~p"/api/runs/#{run.id}/retries", %{step_id: step.id}, 201}
      end,
      fn ->
        %{workflow: workflow, job_a: job} = graph.()

        {:post,
         ~p"/api/projects/#{project.id}/workflows/#{workflow.id}/work_orders",
         %{job_id: job.id}, 201}
      end,
      fn ->
        {:post, ~p"/api/projects/#{project.id}/work_orders/retries",
         %{work_order_ids: [ran.().work_order.id]}, 202}
      end,
      fn ->
        {:post, ~p"/api/projects/#{project.id}/work_orders/cancellations",
         %{work_order_ids: [pending.().id]}, 202}
      end,
      fn ->
        {:patch, ~p"/api/work_orders/#{pending.().id}", %{state: "cancelled"},
         200}
      end,
      fn ->
        {:post, ~p"/api/projects/#{project.id}/history_exports", %{}, 202}
      end
    ]
  end

  # As assert_each_kind/4, for a write `request` (one of history_writes/1)
  # built afresh for each kind. A kind that logs in is answered the route's
  # success status.
  defp assert_each_kind_acting_on_history(conn, tokens, request, expected) do
    assert Enum.sort(Keyword.keys(expected)) == Enum.sort(Keyword.keys(tokens))

    for {kind, answer} <- expected do
      {method, path, body, status} = request.()

      conn =
        conn
        |> put_req_header("content-type", "application/json")
        |> with_token(tokens[kind])
        |> dispatch(@endpoint, method, path, Jason.encode!(body))

      case answer do
        :logs_in ->
          assert conn.status == status,
                 "#{kind} on #{method} #{path} was answered #{conn.status}"

        :invalid_token ->
          assert_unauthenticated(conn, :invalid_token, @invalid_token)

        :expired_token ->
          assert_unauthenticated(conn, :invalid_token, @expired_token)

        :forbidden ->
          assert_problem(conn, 403, :forbidden, [])
          assert get_resp_header(conn, "www-authenticate") == []
      end
    end
  end

  # assert_each_kind/4 for a POST of `body`, where a token that gets through
  # is answered `{:status, status}`.
  defp assert_each_kind_posting_ai(conn, tokens, path, body, expected) do
    assert Enum.sort(Keyword.keys(expected)) == Enum.sort(Keyword.keys(tokens))

    for {kind, answer} <- expected do
      conn = conn |> with_token(tokens[kind]) |> post(path, body)

      case answer do
        {:status, status} ->
          assert conn.status == status, "#{kind} was answered #{conn.status}"

        :expired_token ->
          assert_unauthenticated(conn, :invalid_token, @expired_token)

        :invalid_token ->
          assert_unauthenticated(conn, :invalid_token, @invalid_token)

        :forbidden ->
          assert_problem(conn, 403, :forbidden, [])
          assert get_resp_header(conn, "www-authenticate") == []
      end
    end
  end

  # The same as assert_each_kind/4 for a DELETE, which succeeds with any 2xx.
  # It sends the service account's token first, so the kinds refused after it
  # find the record as it left it.
  defp assert_each_kind_deleting(conn, tokens, path, expected) do
    assert Enum.sort(Keyword.keys(expected)) == Enum.sort(Keyword.keys(tokens))

    for {kind, answer} <- expected do
      conn = conn |> with_token(tokens[kind]) |> delete(path)

      case answer do
        :logs_in ->
          assert conn.status in 200..299, "#{kind} was answered #{conn.status}"

        :invalid_token ->
          assert_unauthenticated(conn, :invalid_token, @invalid_token)

        :expired_token ->
          assert_unauthenticated(conn, :invalid_token, @expired_token)

        :forbidden ->
          assert_problem(conn, 403, :forbidden, [])
          assert get_resp_header(conn, "www-authenticate") == []

        {:insufficient_scope, grant} ->
          assert_refused_for_scope(conn, grant)
      end
    end
  end

  # A path is read with GET; any other request is a function of the conn.
  defp request(conn, path) when is_binary(path), do: get(conn, path)
  defp request(conn, request), do: request.(conn)

  defp with_token(conn, {:session, user}), do: session_conn(conn, user)

  defp with_token(conn, token),
    do: put_req_header(conn, "authorization", "Bearer " <> token)

  defp assert_invalid_request(conn) do
    assert_problem(conn, 400, :invalid_request, [])

    assert get_resp_header(conn, "www-authenticate") == [
             ~s(Bearer error="invalid_request")
           ]
  end

  defp api_method(key) do
    %WebhookAuthMethod{auth_type: :api, api_key: key}
  end

  defp basic_method(username, password) do
    %WebhookAuthMethod{auth_type: :basic, username: username, password: password}
  end

  defp with_header(conn, key, value) do
    Plug.Conn.put_req_header(conn, key, value)
  end

  describe "valid_key?/2" do
    test "returns true for correct API key" do
      conn = conn(:get, "/") |> with_header("x-api-key", "my-secret")

      assert Auth.valid_key?(conn, [api_method("my-secret")])
    end

    test "returns false for wrong API key" do
      conn = conn(:get, "/") |> with_header("x-api-key", "wrong")

      refute Auth.valid_key?(conn, [api_method("my-secret")])
    end

    test "returns false when no x-api-key header" do
      conn = conn(:get, "/")

      refute Auth.valid_key?(conn, [api_method("my-secret")])
    end

    test "ignores non-api auth methods" do
      conn = conn(:get, "/") |> with_header("x-api-key", "anything")

      refute Auth.valid_key?(conn, [basic_method("user", "pass")])
    end

    test "matches any of multiple API key methods" do
      conn = conn(:get, "/") |> with_header("x-api-key", "key-2")

      assert Auth.valid_key?(conn, [
               api_method("key-1"),
               api_method("key-2")
             ])
    end
  end

  describe "valid_user?/2" do
    test "returns true for correct Basic Auth credentials" do
      encoded = Base.encode64("admin:secret123")
      conn = conn(:get, "/") |> with_header("authorization", "Basic #{encoded}")

      assert Auth.valid_user?(conn, [basic_method("admin", "secret123")])
    end

    test "returns false for wrong credentials" do
      encoded = Base.encode64("admin:wrong")
      conn = conn(:get, "/") |> with_header("authorization", "Basic #{encoded}")

      refute Auth.valid_user?(conn, [basic_method("admin", "secret123")])
    end

    test "returns false for wrong username" do
      encoded = Base.encode64("notadmin:secret123")
      conn = conn(:get, "/") |> with_header("authorization", "Basic #{encoded}")

      refute Auth.valid_user?(conn, [basic_method("admin", "secret123")])
    end

    test "returns false when no authorization header" do
      conn = conn(:get, "/")

      refute Auth.valid_user?(conn, [basic_method("admin", "pass")])
    end

    test "returns false for malformed Authorization header" do
      conn =
        conn(:get, "/") |> with_header("authorization", "Basic !!!notbase64")

      refute Auth.valid_user?(conn, [basic_method("admin", "pass")])
    end

    test "returns false for non-Basic scheme" do
      conn = conn(:get, "/") |> with_header("authorization", "Bearer token123")

      refute Auth.valid_user?(conn, [basic_method("admin", "pass")])
    end

    test "ignores non-basic auth methods" do
      encoded = Base.encode64("admin:pass")
      conn = conn(:get, "/") |> with_header("authorization", "Basic #{encoded}")

      refute Auth.valid_user?(conn, [api_method("some-key")])
    end

    test "matches any of multiple basic methods" do
      encoded = Base.encode64("user2:pass2")
      conn = conn(:get, "/") |> with_header("authorization", "Basic #{encoded}")

      assert Auth.valid_user?(conn, [
               basic_method("user1", "pass1"),
               basic_method("user2", "pass2")
             ])
    end
  end

  describe "has_credentials?/1" do
    test "detects x-api-key header" do
      conn = conn(:get, "/") |> with_header("x-api-key", "anything")

      assert Auth.has_credentials?(conn)
    end

    test "detects authorization header" do
      conn = conn(:get, "/") |> with_header("authorization", "Basic abc")

      assert Auth.has_credentials?(conn)
    end

    test "returns false when no auth headers present" do
      conn = conn(:get, "/")

      refute Auth.has_credentials?(conn)
    end
  end

  describe "auth methods scheduled for deletion" do
    setup do
      %{revoked_at: DateTime.utc_now() |> Timex.shift(days: 7)}
    end

    test "valid_key? rejects a revoked API key", %{revoked_at: revoked_at} do
      conn = conn(:get, "/") |> with_header("x-api-key", "my-secret")

      revoked = %{api_method("my-secret") | scheduled_deletion: revoked_at}

      refute Auth.valid_key?(conn, [revoked])
    end

    test "valid_key? still accepts a live key alongside a revoked one", %{
      revoked_at: revoked_at
    } do
      conn = conn(:get, "/") |> with_header("x-api-key", "live-key")

      revoked = %{api_method("revoked-key") | scheduled_deletion: revoked_at}

      assert Auth.valid_key?(conn, [revoked, api_method("live-key")])
    end

    test "valid_user? rejects revoked basic credentials", %{
      revoked_at: revoked_at
    } do
      encoded = Base.encode64("admin:secret123")
      conn = conn(:get, "/") |> with_header("authorization", "Basic #{encoded}")

      revoked = %{
        basic_method("admin", "secret123")
        | scheduled_deletion: revoked_at
      }

      refute Auth.valid_user?(conn, [revoked])
    end
  end
end
