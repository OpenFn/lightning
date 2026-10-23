defmodule LightningWeb.AuthTest do
  @moduledoc """
  One route per JSON pipeline, refused for no token, for a bad one and for a
  `Bearer` header it can't read, which token kinds each pipeline takes, a
  locked-out account on a bearer pipeline, and the bearer scheme read without
  regard to case on one route per auth plug. Then the checks of a request
  against webhook auth methods.
  """
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
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
        access_token_api: "/api/users",
        person_or_service_account_api:
          "/api/projects/7b0c1b4c-0c62-4b8e-9a39-0a6c9e1f2d11",
        api: "/api/projects",
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
          run: Lightning.Workers.generate_run_token(run)
        ]
      }
    end

    test "access_token_api takes only a service account's access token",
         %{conn: conn, tokens: tokens} do
      assert_each_kind(conn, tokens, ~p"/api/users",
        service_account: :logs_in,
        expired_service_account: :invalid_token,
        personal: :invalid_token,
        repo_connection: :invalid_token,
        run: :invalid_token
      )
    end

    test "person_or_service_account_api takes a service account's or a person's token, and not a run token",
         %{conn: conn, tokens: tokens, project: project} do
      assert_each_kind(conn, tokens, ~p"/api/projects/#{project.id}",
        service_account: :logs_in,
        expired_service_account: :invalid_token,
        personal: :logs_in,
        repo_connection: {:insufficient_scope, "projects:write"},
        run: :invalid_token
      )
    end

    test "the :api scope takes a personal or repo connection token only",
         %{conn: conn, tokens: tokens} do
      assert_each_kind(conn, tokens, ~p"/api/projects",
        service_account: :invalid_token,
        expired_service_account: :invalid_token,
        personal: :logs_in,
        repo_connection: {:insufficient_scope, "projects:write"},
        run: :invalid_token
      )
    end

    test "authenticated_api takes a personal or run token, and not a repo connection's or a service account's",
         %{conn: conn, tokens: tokens, collection: collection} do
      assert_each_kind(conn, tokens, ~p"/collections/#{collection.name}",
        service_account: :invalid_token,
        expired_service_account: :invalid_token,
        personal: :logs_in,
        repo_connection: :invalid_token,
        run: :logs_in
      )
    end

    test "authenticated_json takes no bearer token of any kind", %{
      conn: conn,
      tokens: tokens
    } do
      for {_kind, token} <- tokens do
        conn =
          conn
          |> put_req_header("authorization", "Bearer " <> token)
          |> get(~p"/api/ai_assistant/sessions")

        assert_session_refused(conn)
      end
    end
  end

  defp assert_each_kind(conn, tokens, path, expected) do
    assert Enum.sort(Keyword.keys(expected)) == Enum.sort(Keyword.keys(tokens))

    for {kind, answer} <- expected do
      conn =
        conn
        |> put_req_header("authorization", "Bearer " <> tokens[kind])
        |> get(path)

      case answer do
        :logs_in ->
          assert conn.status == 200, "#{kind} was answered #{conn.status}"

        :invalid_token ->
          assert_unauthenticated(conn, :invalid_token, @invalid_token)

        {:insufficient_scope, grant} ->
          assert_refused_for_scope(conn, grant)
      end
    end
  end

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
