defmodule LightningWeb.API.BeforeTheRouterTest do
  @moduledoc """
  The answers Lightning gives before a controller runs, on each JSON pipeline
  (error-format spec §4, §5, §9.3, §9.5).
  """
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Lightning.ServiceAccountHelpers
  import LightningWeb.API.ProblemHelpers

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

  defp assert_problem_sent({status, headers, body}, code) do
    assert status == Codes.status(code)

    assert {"content-type", "application/json; charset=utf-8"} in headers

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
        |> assert_problem(400, :malformed)
      end
    end

    test "follows Accept", %{conn: conn} do
      conn
      |> put_req_header("accept", "application/problem+json")
      |> send_body(hd(@body_routes), "application/json", "{")
      |> assert_problem(400, :malformed)
    end
  end

  describe "a body over the size limit" do
    test "is 413 too_large on every pipeline", %{conn: conn} do
      body = too_large_body()

      for route <- @body_routes do
        conn
        |> send_body(route, "application/json", body)
        |> assert_problem(413, :too_large)
      end
    end
  end

  describe "a body no parser reads" do
    test "is 415 unsupported_media_type on every pipeline", %{conn: conn} do
      for route <- @parsed_routes do
        conn
        |> send_body(route, "text/plain", "hello")
        |> assert_problem(415, :unsupported_media_type)
      end
    end
  end

  describe "an unmatched route" do
    test "is 404 not_found as JSON, not HTML, with no Accept header", %{
      conn: conn
    } do
      for path <- ["/api/nothing-here", "/api/users/a/b", "/collections/a/b/c"] do
        conn = get(conn, path)

        assert_problem(conn, 404, :not_found)
        refute conn.resp_body =~ "<"
      end
    end

    test "follows Accept, ahead of authentication", %{conn: conn} do
      conn
      |> put_req_header("accept", "application/problem+json")
      |> delete("/collections/a/b/c")
      |> assert_problem(404, :not_found)
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
    test "is 404 not_found on the service-account pipeline", %{conn: conn} do
      {account, _private_key} = service_account_with_key()
      Mox.stub(Lightning.MockConfig, :service_account, fn -> account end)

      conn
      |> assign_bearer(AccessToken.issue(account, ["users:read"]))
      |> get("/api/users/not-a-uuid")
      |> assert_problem(404, :not_found)
    end

    test "is 404 not_found on the person-or-service-account pipeline", %{
      conn: conn
    } do
      conn
      |> assign_bearer(insert(:user))
      |> get("/api/projects/not-a-uuid")
      |> assert_problem(404, :not_found)
    end

    test "is 404 not_found where the query raises Ecto.Query.CastError", %{
      conn: conn
    } do
      conn = assign_bearer(conn, insert(:user))

      for path <- ["/api/jobs/not-a-uuid", "/api/runs/not-a-uuid"] do
        assert_error_sent(404, fn -> get(conn, path) end)
        |> assert_problem_sent(:not_found)
      end
    end
  end

  describe "render_errors" do
    test "answers a 406 with a problem document as JSON", %{conn: conn} do
      assert_error_sent(406, fn ->
        conn |> put_req_header("accept", "text/html") |> get("/api/users")
      end)
      |> assert_problem_sent(:not_acceptable)
    end
  end

  describe "a path the format doesn't cover" do
    test "re-raises a body that isn't JSON", %{conn: conn} do
      %{triggers: [trigger]} =
        insert(:simple_workflow) |> Lightning.Repo.preload(:triggers)

      assert_raise Plug.Parsers.ParseError, fn ->
        send_body(conn, {:post, "/i/#{trigger.id}"}, "application/json", "{")
      end
    end
  end
end
