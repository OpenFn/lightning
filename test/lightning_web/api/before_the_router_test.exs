defmodule LightningWeb.API.BeforeTheRouterTest do
  @moduledoc """
  The answers Lightning gives before a controller runs, on each JSON pipeline
  (error-format spec §4, §5, §9.3, §9.5).
  """
  use LightningWeb.ConnCase, async: true
  use Mimic

  import Lightning.Factories
  import Lightning.ServiceAccountHelpers
  import LightningWeb.API.ProblemHelpers

  alias Lightning.Extensions.MockRateLimiter
  alias Lightning.Projects.Provisioner
  alias Lightning.ServiceAccount.AccessToken
  alias LightningWeb.API.Codes

  # One route per pipeline that takes a body: access_token_api,
  # person_or_service_account_api, api, authenticated_json (no route there
  # takes a body, but the endpoint answers before routing) and
  # authenticated_api.
  @body_routes [
    {:post, "/api/users"},
    {:put, "/api/projects/#{Ecto.UUID.generate()}"},
    {:post, "/api/provision"},
    {:post, "/api/ai_assistant/sessions"},
    {:post, "/collections/a-collection"}
  ]

  # authenticated_json has no route that takes a body, so nothing there can
  # reach the 415.
  @parsed_routes List.delete_at(@body_routes, 3)

  defp send_body(conn, {method, path}, content_type, body) do
    conn
    |> put_req_header("content-type", content_type)
    |> dispatch(@endpoint, method, path, body)
  end

  defp too_large_body do
    limit = Application.fetch_env!(:lightning, :max_dataclip_size_bytes)
    ~s(") <> String.duplicate("a", max(limit, 10_000_000) + 1) <> ~s(")
  end

  defp assert_problem_sent({status, headers, body}, code, media_type) do
    assert status == Codes.status(code)

    assert {"content-type", "#{media_type}; charset=utf-8"} in headers

    assert %{"status" => ^status, "code" => code_name, "detail" => detail} =
             Jason.decode!(body)

    assert code_name == Atom.to_string(code)
    assert detail == Codes.detail(code)
  end

  describe "a body that isn't JSON" do
    test "is 400 malformed on every pipeline", %{conn: conn} do
      for route <- @body_routes do
        conn
        |> send_body(route, "application/json", ~s({"name": ))
        |> assert_problem(400, :malformed, [])
      end
    end

    test "follows Accept", %{conn: conn} do
      conn
      |> put_req_header("accept", "application/problem+json")
      |> send_body(hd(@body_routes), "application/json", "{")
      |> assert_problem(400, :malformed, [])
    end
  end

  describe "a request the parsers can't decode" do
    test "is 400 bad_request for a query string, whatever Accept asks", %{
      conn: conn
    } do
      conn
      |> get("/api/runs?a=%FF")
      |> assert_problem(400, :bad_request, [])

      conn
      |> put_req_header("accept", "application/json")
      |> get("/api/runs?a=%FF")
      |> assert_problem(400, :bad_request, [])
    end

    test "is 414 uri_too_long for a query string over Plug's limit", %{
      conn: conn
    } do
      conn
      |> get("/api/runs?a=" <> String.duplicate("a", 1_000_000))
      |> assert_problem(414, :uri_too_long, [])
    end

    test "is 400 bad_request for a form body", %{conn: conn} do
      conn
      |> send_body(
        hd(@body_routes),
        "application/x-www-form-urlencoded",
        "a=%FF"
      )
      |> assert_problem(400, :bad_request, [])
    end
  end

  describe "a body over the size limit" do
    test "is 413 content_too_large on every pipeline", %{conn: conn} do
      body = too_large_body()

      for route <- @body_routes do
        conn
        |> send_body(route, "application/json", body)
        |> assert_problem(413, :content_too_large, [])
      end
    end
  end

  describe "an error raised before the router, from an allowed Origin" do
    setup %{conn: conn} do
      Mox.stub(Lightning.MockConfig, :cors_origin, fn ->
        ["https://app.example.com"]
      end)

      %{conn: put_req_header(conn, "origin", "https://app.example.com")}
    end

    defp assert_cors_and_request_id(conn) do
      assert get_resp_header(conn, "access-control-allow-origin") == [
               "https://app.example.com"
             ]

      assert [_request_id] = get_resp_header(conn, "x-request-id")
    end

    test "an answer from the router carries CORS and a request id", %{
      conn: conn
    } do
      conn
      |> get("/api/nothing-here")
      |> tap(&assert_problem(&1, 404, :not_found, []))
      |> assert_cors_and_request_id()
    end

    test "still carries CORS and a request id on a 400 or 413", %{conn: conn} do
      for path <- ["/api/users", "/collections/a-collection"],
          {body, status, code} <- [
            {"{", 400, :malformed},
            {too_large_body(), 413, :content_too_large}
          ] do
        conn
        |> send_body({:post, path}, "application/json", body)
        |> tap(&assert_problem(&1, status, code, []))
        |> assert_cors_and_request_id()
      end
    end

    test "answers a preflight that raises with the error, not a 204", %{
      conn: conn
    } do
      # The bad query string raises in LiveDashboard's RequestLogger, which runs
      # ahead of CORSPlug, so the preflight never reaches CORSPlug's 204.
      conn
      |> put_req_header("access-control-request-method", "GET")
      |> options("/api/runs?a=%FF")
      |> tap(&assert_problem(&1, 400, :bad_request, []))
      |> assert_cors_and_request_id()
    end

    test "answers with the request id the request's log lines carry", %{
      conn: conn
    } do
      test_pid = self()

      # CORSPlug reads the allowed origins after Plug.RequestId has set the
      # id, so this sees the request's logged id before anything raises.
      Mox.stub(Lightning.MockConfig, :cors_origin, fn ->
        send(test_pid, {:logged_request_id, Logger.metadata()[:request_id]})
        ["https://app.example.com"]
      end)

      conn = send_body(conn, {:post, "/api/users"}, "application/json", "{")

      assert_received {:logged_request_id, logged_request_id}
      assert is_binary(logged_request_id)
      assert get_resp_header(conn, "x-request-id") == [logged_request_id]
    end

    test "carries no CORS for an Origin that isn't allowed", %{conn: conn} do
      for path <- ["/api/users", "/collections/a-collection"],
          body <- ["{", too_large_body()] do
        conn =
          conn
          |> put_req_header("origin", "https://elsewhere.example.com")
          |> send_body({:post, path}, "application/json", body)

        assert get_resp_header(conn, "access-control-allow-origin") == []
        assert [_request_id] = get_resp_header(conn, "x-request-id")
      end
    end
  end

  describe "a body no parser reads" do
    test "is 415 unsupported_media_type on every pipeline", %{conn: conn} do
      for route <- @parsed_routes do
        conn
        |> send_body(route, "text/plain", "hello")
        |> assert_problem(415, :unsupported_media_type, [])
      end
    end

    test "is not refused when there is no body, whatever its content type", %{
      conn: conn
    } do
      for route <- @parsed_routes do
        conn
        |> send_body(route, "text/plain", "")
        |> assert_problem(401, :unauthenticated, [])
      end
    end

    test "lets a DELETE with no body reach its controller", %{conn: conn} do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])

      collection =
        insert(:collection,
          project: project,
          items: [%{key: "foo", value: "bar"}]
        )

      conn =
        conn
        |> assign_bearer(user)
        |> send_body(
          {:delete, "/collections/#{collection.name}/foo"},
          "text/plain",
          ""
        )

      assert %{"key" => "foo", "deleted" => 1} = json_response(conn, 200)
    end
  end

  describe "an unmatched route" do
    test "is 404 not_found as JSON, not HTML, with no Accept header", %{
      conn: conn
    } do
      for path <- ["/api/nothing-here", "/api/users/a/b", "/collections/a/b/c"] do
        conn = get(conn, path)

        assert_problem(conn, 404, :not_found, [])
        refute conn.resp_body =~ "<"
      end
    end

    test "follows Accept, ahead of authentication", %{conn: conn} do
      conn
      |> put_req_header("accept", "application/problem+json")
      |> delete("/collections/a/b/c")
      |> assert_problem(404, :not_found, [])
    end

    test "on the OAuth token endpoint stays the router's own 404", %{
      conn: conn
    } do
      conn = get(conn, "/api/oauth/token")

      assert conn.status == 404
      refute conn.resp_body =~ "not_found"
    end
  end

  describe "a path id that isn't a UUID" do
    test "is 400 invalid_parameter on the service-account pipeline", %{
      conn: conn
    } do
      {account, _private_key} = service_account_with_key()
      Mox.stub(Lightning.MockConfig, :service_account, fn -> account end)

      conn
      |> assign_bearer(AccessToken.issue(account, ["users:read"]))
      |> get("/api/users/not-a-uuid")
      |> assert_problem(400, :invalid_parameter, [
        not_a_uuid_entry(%{"path" => "id"})
      ])
    end

    test "is 403 forbidden on the person-or-service-account pipeline, to a person who isn't a superuser",
         %{conn: conn} do
      conn
      |> assign_bearer(insert(:user))
      |> get("/api/projects/not-a-uuid")
      |> assert_problem(403, :forbidden, [])
    end

    test "is 403 forbidden where the controller casts the id, to a person who isn't a superuser",
         %{conn: conn} do
      conn
      |> assign_bearer(insert(:user))
      |> get("/api/jobs/not-a-uuid")
      |> assert_problem(403, :forbidden, [])
    end
  end

  describe "a raise on a problem path" do
    setup %{conn: conn} do
      stub(Provisioner, :import_document, fn _project, _actor, _document ->
        raise "raised for a test"
      end)

      %{conn: assign_bearer(conn, insert(:user, role: :superuser))}
    end

    defp provision(conn), do: post(conn, "/api/provision", %{"name" => "a"})

    test "is 500 internal, and still raises", %{conn: conn} do
      assert_error_sent(500, fn ->
        conn |> put_req_header("accept", "*/*") |> provision()
      end)
      |> assert_problem_sent(:internal, "application/json")
    end

    test "follows Accept", %{conn: conn} do
      assert_error_sent(500, fn ->
        conn
        |> put_req_header("accept", "application/problem+json")
        |> provision()
      end)
      |> assert_problem_sent(:internal, "application/problem+json")
    end

    test "answers a 406 with a problem document as JSON", %{conn: conn} do
      conn = conn |> put_req_header("accept", "text/html") |> get("/api/users")

      assert_problem(conn, 406, :not_acceptable, [])

      assert ["application/json; charset=utf-8"] =
               get_resp_header(conn, "content-type")
    end
  end

  describe "a path the format doesn't cover" do
    test "keeps Phoenix's answer to a 500", %{conn: conn} do
      Mox.stub(Lightning.MockConfig, :check_flag?, fn _flag ->
        raise "raised for a test"
      end)

      {500, headers, body} =
        assert_error_sent(500, fn -> get(conn, "/users/log_in") end)

      assert {"content-type", "text/html; charset=utf-8"} in headers
      refute body =~ "internal"
    end

    test "keeps ErrorView's JSON 500 on a webhook with no Accept", %{
      conn: conn
    } do
      Mox.stub(MockRateLimiter, :limit_request, fn _conn, _context, _opts ->
        raise "raised for a test"
      end)

      %{triggers: [trigger]} =
        insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

      {500, headers, body} =
        assert_error_sent(500, fn -> post(conn, "/i/#{trigger.id}") end)

      assert {"content-type", "application/json; charset=utf-8"} in headers
      assert Jason.decode!(body) == %{"error" => "Internal Server Error"}
    end

    test "re-raises a body that isn't JSON", %{conn: conn} do
      assert_raise Plug.Parsers.ParseError, fn ->
        send_body(conn, {:post, "/users/log_in"}, "application/json", "{")
      end
    end

    test "re-raises a query string it can't decode", %{conn: conn} do
      {400, headers, _body} =
        assert_error_sent(400, fn -> get(conn, "/users/log_in?a=%FF") end)

      assert {"content-type", "text/html; charset=utf-8"} in headers
    end

    test "keeps phoenix_ecto's 400 for a path id that isn't a UUID", %{
      conn: conn
    } do
      {400, headers, body} =
        assert_error_sent(400, fn ->
          conn
          |> log_in_user(insert(:user))
          |> get("/project_files/not-a-uuid/download")
        end)

      assert {"content-type", "text/html; charset=utf-8"} in headers
      refute body =~ "not_found"
    end
  end
end
