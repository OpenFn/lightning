defmodule LightningWeb.Plugs.PersonOrServiceAccountAuthTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

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

  describe "GET /api/projects/:id" do
    test "refuses an expired service-account token with 401 invalid_token", %{
      conn: conn,
      account: account
    } do
      conn =
        conn
        |> with_token(expired_access_token(account, "projects:write"))
        |> get(~p"/api/projects/#{insert(:project).id}")

      assert_problem(conn, 401, :invalid_token, [])

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

    test "refuses a non-member's personal access token with 404", %{
      conn: conn
    } do
      user = insert(:user)
      project = insert(:project)

      conn =
        conn
        |> with_token(Lightning.Accounts.generate_api_token(user))
        |> get(~p"/api/projects/#{project.id}")

      assert_problem(conn, 404, :not_found, [])
      assert get_resp_header(conn, "www-authenticate") == []
    end
  end
end
