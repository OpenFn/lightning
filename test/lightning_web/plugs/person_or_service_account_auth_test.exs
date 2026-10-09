defmodule LightningWeb.Plugs.PersonOrServiceAccountAuthTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  alias Lightning.ServiceAccount.AccessToken
  alias LightningWeb.Plugs.PersonOrServiceAccountAuth

  setup %{conn: conn} do
    {account, _private_key} = service_account_with_key()
    Mox.stub(Lightning.MockConfig, :service_account, fn -> account end)

    %{
      conn: put_req_header(conn, "accept", "application/json"),
      account: account
    }
  end

  defp with_token(conn, token),
    do: put_req_header(conn, "authorization", "Bearer " <> token)

  defp with_scopes(conn, account, scopes),
    do: with_token(conn, AccessToken.issue(account, scopes))

  describe "GET /api/projects/:id" do
    test "refuses a service account without projects:write with 403", %{
      conn: conn,
      account: account
    } do
      project = insert(:project)

      conn =
        conn
        |> with_scopes(account, ["users:read", "users:write"])
        |> get(~p"/api/projects/#{project.id}")

      assert json_response(conn, 403) == %{"error" => "insufficient_scope"}

      assert get_resp_header(conn, "www-authenticate") == [
               ~s(Bearer error="insufficient_scope")
             ]
    end

    test "refuses an expired service-account token with 401 invalid_token", %{
      conn: conn,
      account: account
    } do
      {_, token} =
        Lightning.Config.token_signer().jwk
        |> JOSE.JWT.sign(%{"alg" => "RS256", "typ" => "at+jwt"}, %{
          "iss" => AccessToken.issuer(),
          "aud" => AccessToken.issuer() <> "/api",
          "sub" => account.id,
          "scope" => "projects:write",
          "exp" => System.system_time(:second) - 1
        })
        |> JOSE.JWS.compact()

      conn =
        conn
        |> with_token(token)
        |> get(~p"/api/projects/#{insert(:project).id}")

      assert json_response(conn, 401) == %{"error" => "invalid_token"}

      assert get_resp_header(conn, "www-authenticate") == [
               ~s(Bearer error="invalid_token")
             ]
    end

    test "shows a project to a member's personal access token", %{conn: conn} do
      user = insert(:user)
      project = insert(:project, project_users: [%{user: user}])

      conn =
        conn
        |> with_token(Lightning.Accounts.generate_api_token(user))
        |> get(~p"/api/projects/#{project.id}")

      assert %{"id" => id} = json_response(conn, 200)["data"]
      assert id == project.id
    end

    test "refuses a non-member's personal access token with 401", %{
      conn: conn
    } do
      user = insert(:user)
      project = insert(:project)

      conn =
        conn
        |> with_token(Lightning.Accounts.generate_api_token(user))
        |> get(~p"/api/projects/#{project.id}")

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
      assert get_resp_header(conn, "www-authenticate") == []
    end

    test "refuses a garbage token with 401", %{conn: conn} do
      conn =
        conn
        |> with_token("Oooops")
        |> get(~p"/api/projects/#{insert(:project).id}")

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end

    test "refuses a request without a token with 401", %{conn: conn} do
      conn = get(conn, ~p"/api/projects/#{insert(:project).id}")

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  describe "routes outside /api/projects/:id" do
    setup %{conn: conn, account: account} do
      %{conn: with_scopes(conn, account, AccessToken.scopes())}
    end

    test "refuse a service account on POST /api/provision with 401", %{
      conn: conn
    } do
      conn = post(conn, ~p"/api/provision", %{})

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end

    test "refuse a service account on GET /api/projects with 401", %{
      conn: conn
    } do
      conn = get(conn, ~p"/api/projects")

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end

    test "refuse a service account on GET /api/projects/:id/workflows with 401",
         %{conn: conn} do
      conn = get(conn, ~p"/api/projects/#{insert(:project).id}/workflows")

      assert json_response(conn, 401) == %{"error" => "Unauthorized"}
    end
  end

  # The plugs on their own: what the policy then answers is pinned in
  # project_controller_test.exs.
  describe "a repo connection token" do
    test "is authenticated and passes require_scope", %{conn: conn} do
      repo_connection =
        insert(:project_repo_connection, project: insert(:project))

      conn =
        conn
        |> with_token(repo_connection.access_token)
        |> PersonOrServiceAccountAuth.call([])
        |> PersonOrServiceAccountAuth.require_scope("projects:write")

      refute conn.halted
      assert conn.assigns.current_resource.id == repo_connection.id
    end
  end
end
