defmodule LightningWeb.SessionTokenTest do
  @moduledoc """
  The session token on the bearer API pipeline: which requests it
  authenticates, how a write without its CSRF token is refused, that it acts
  as the person like a personal access token, and how a route that takes only
  a session token, or a stepped-up one, refuses everything else. Bearer token
  kinds are in `LightningWeb.AuthTest`.
  """
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  alias Lightning.Accounts
  alias Lightning.Config.API, as: ConfigAPI
  alias Lightning.Policies.Decision
  alias Lightning.ServiceAccount.AccessToken
  alias LightningWeb.Plugs.AuthorizeAction
  alias LightningWeb.Plugs.PersonOrServiceAccountAuth

  defmodule SessionOnlyPolicy do
    @moduledoc false
    @behaviour Bodyguard.Policy

    def authorize(:manage_account, scope, _subject),
      do: Decision.session(scope, true)

    def authorize(:turn_off_mfa, scope, _subject),
      do: Decision.session(scope, true, step_up: true)
  end

  setup do
    user = insert(:user)
    project = insert(:project, project_users: [%{user: user, role: :owner}])
    %{user: user, project: project}
  end

  describe "a session token on the bearer pipeline" do
    test "reads as the person when it comes from Lightning's own page",
         %{user: user, project: project} do
      conn =
        build_conn()
        |> session_conn(user)
        |> get(~p"/api/projects/#{project.id}")

      assert %{"data" => %{"id" => id}} = json_response(conn, 200)
      assert id == project.id
    end

    test "comes from Lightning's own page by its Origin when the browser sends no Sec-Fetch-Site",
         %{user: user, project: project} do
      conn =
        build_conn()
        |> session_conn(user, origin: :none)
        |> put_req_header("origin", LightningWeb.Endpoint.url())
        |> get(~p"/api/projects/#{project.id}")

      assert json_response(conn, 200)["data"]["id"] == project.id
    end

    test "counts for nothing from another site, or with no sign of where it came from",
         %{user: user, project: project} do
      for conn <- [
            session_conn(build_conn(), user, origin: :cross),
            build_conn()
            |> session_conn(user, origin: :none)
            |> put_req_header("origin", "https://elsewhere.example.com"),
            session_conn(build_conn(), user, origin: :none),
            build_conn()
            |> session_conn(user)
            |> put_req_header("sec-fetch-site", "same-site")
          ] do
        conn
        |> get(~p"/api/projects/#{project.id}")
        |> assert_unauthenticated(:unauthenticated, ["Bearer"])
      end
    end

    test "counts for nothing while its MFA code is pending, or once revoked, or for a disabled account",
         %{project: project} do
      pending = insert(:user, mfa_enabled: true)
      revoked = insert(:user)
      disabled = insert(:user)

      for user <- [pending, revoked, disabled] do
        insert(:project_user, project: project, user: user)
      end

      revoked_conn = session_conn(build_conn(), revoked)
      Accounts.delete_session_token(get_session(revoked_conn, :user_token))
      Lightning.Repo.update!(Ecto.Changeset.change(disabled, disabled: true))

      for conn <- [
            session_conn(build_conn(), pending, mfa_pending: true),
            revoked_conn,
            session_conn(build_conn(), disabled)
          ] do
        conn
        |> get(~p"/api/projects/#{project.id}")
        |> assert_unauthenticated(:unauthenticated, ["Bearer"])
      end
    end

    test "counts for nothing for an account past its confirmation deadline",
         %{project: project} do
      Mox.stub(Lightning.MockConfig, :check_flag?, fn
        :require_email_verification -> true
        flag -> ConfigAPI.check_flag?(flag)
      end)

      user =
        insert(:user,
          confirmed_at: nil,
          inserted_at: DateTime.add(DateTime.utc_now(), -49, :hour)
        )

      insert(:project_user, project: project, user: user)

      build_conn()
      |> session_conn(user)
      |> get(~p"/api/projects/#{project.id}")
      |> assert_unauthenticated(:unauthenticated, ["Bearer"])
    end

    test "is ignored when the request sends an Authorization header",
         %{user: user, project: project} do
      build_conn()
      |> session_conn(user)
      |> put_req_header("authorization", "Bearer not-a-token")
      |> get(~p"/api/projects/#{project.id}")
      |> assert_unauthenticated(:invalid_token, [
        ~s(Bearer error="invalid_token")
      ])
    end

    test "writes once the session's CSRF token is sent", %{
      user: user,
      project: project
    } do
      build_conn()
      |> session_conn(user)
      |> post(~p"/api/projects/#{project.id}/workflows", "[1]")
      |> assert_problem(400, :malformed, [])
    end

    test "refuses a write without the session's CSRF token, before reading the body",
         %{user: user, project: project} do
      for {conn, code, detail} <- [
            {session_conn(build_conn(), user, csrf: false), "required",
             "can't be blank"},
            {build_conn()
             |> session_conn(user, csrf: false)
             |> put_req_header("x-csrf-token", "not-the-token"), "mismatch",
             "does not match the session"},
            {build_conn()
             |> session_conn(user)
             |> put_session("_csrf_token", nil), "mismatch",
             "does not match the session"}
          ] do
        conn
        |> post(~p"/api/projects/#{project.id}/workflows", "[1]")
        |> assert_problem(400, :invalid_header, [
          %{"header" => "x-csrf-token", "code" => code, "detail" => detail}
        ])
      end
    end

    test "is turned away by a project that requires MFA the person hasn't set up" do
      user = insert(:user, mfa_enabled: false)

      project =
        insert(:project,
          requires_mfa: true,
          project_users: [%{user: user, role: :owner}]
        )

      build_conn()
      |> session_conn(user)
      |> get(~p"/api/projects/#{project.id}")
      |> assert_problem(403, :forbidden, [])
    end
  end

  describe "a route that takes only a session token" do
    setup %{user: user, project: project} do
      {account, _private_key} = service_account_with_key()
      Mox.stub(Lightning.MockConfig, :service_account, fn -> account end)

      bearer = fn token ->
        build_conn()
        |> put_req_header("accept", "application/json")
        |> put_req_header("authorization", "Bearer " <> token)
      end

      %{
        bearers: [
          bearer.(Accounts.generate_api_token(user)),
          bearer.(AccessToken.issue(account, AccessToken.scopes())),
          bearer.(
            insert(:project_repo_connection, project: project).access_token
          )
        ]
      }
    end

    test "lets a session token through, with its kind on the scope", %{
      user: user
    } do
      conn = build_conn() |> session_conn(user) |> authorize(:manage_account)

      refute conn.halted
      assert %{token_kind: :session, stepped_up_until: nil} = conn.assigns.scope
    end

    test "refuses every bearer token kind with forbidden", %{bearers: bearers} do
      for conn <- bearers, action <- [:manage_account, :turn_off_mfa] do
        conn = authorize(conn, action)

        assert conn.halted
        assert_problem(conn, 403, :forbidden, [])
        assert get_resp_header(conn, "www-authenticate") == []
      end
    end

    test "that needs step-up refuses a session that hasn't stepped up in the last five minutes",
         %{user: user} do
      for conn <- [
            session_conn(build_conn(), user),
            build_conn() |> session_conn(user) |> step_up(user, 301)
          ] do
        conn = authorize(conn, :turn_off_mfa)

        assert conn.halted
        assert_problem(conn, 403, :step_up_required, [])
      end
    end

    test "that needs step-up lets a stepped-up session through", %{user: user} do
      conn =
        build_conn()
        |> session_conn(user, stepped_up: true)
        |> authorize(:turn_off_mfa)

      refute conn.halted

      assert DateTime.after?(
               conn.assigns.scope.stepped_up_until,
               DateTime.utc_now()
             )
    end
  end

  defp authorize(conn, action) do
    conn = Plug.Adapters.Test.Conn.conn(conn, :get, "/api/test", nil)

    case PersonOrServiceAccountAuth.call(conn, []) do
      %{halted: true} = conn -> conn
      conn -> AuthorizeAction.call(conn, {SessionOnlyPolicy, action})
    end
  end
end
