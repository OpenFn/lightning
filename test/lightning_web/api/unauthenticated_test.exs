defmodule LightningWeb.API.UnauthenticatedTest do
  @moduledoc """
  One route per JSON pipeline, refused for no token and for a bad one
  (error-format spec §9.1, §14).
  """
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import Lightning.ServiceAccountHelpers

  @invalid_token [~s(Bearer error="invalid_token")]

  setup %{conn: conn} do
    {account, _private_key} = service_account_with_key()
    Mox.stub(Lightning.MockConfig, :service_account, fn -> account end)

    %{conn: put_req_header(conn, "accept", "application/json")}
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

      test "answers a malformed Authorization header with invalid_token", %{
        conn: conn
      } do
        conn =
          conn
          |> put_req_header("authorization", "Basic dXNlcjpwYXNz")
          |> get(unquote(path))

        assert_unauthenticated(conn, :invalid_token, @invalid_token)
      end
    end
  end

  for path <- [
        "/api/ai_assistant/sessions",
        "/adaptors/catalogue"
      ] do
    describe "the authenticated_json pipeline, GET #{path}" do
      test "answers no session with unauthenticated and no challenge", %{
        conn: conn
      } do
        conn = get(conn, unquote(path))

        assert_unauthenticated(conn, :unauthenticated, [])
      end

      test "answers a bearer token with unauthenticated, since it takes only the cookie",
           %{conn: conn} do
        conn =
          conn
          |> put_req_header("authorization", "Bearer not-a-token")
          |> get(unquote(path))

        assert_unauthenticated(conn, :unauthenticated, [])
      end
    end
  end
end
