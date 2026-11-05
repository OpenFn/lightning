defmodule LightningWeb.Plugs.PersonOrServiceAccountAuthTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  alias Lightning.ServiceAccount.AccessToken

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

  defp get_users(conn, token),
    do: conn |> with_token(token) |> get(~p"/api/users")

  defp assert_refused(conn) do
    assert_unauthenticated(conn, :invalid_token, [
      ~s(Bearer error="invalid_token")
    ])
  end

  defp signed_access_token(claims, typ \\ "at+jwt", key \\ nil) do
    sign_assertion(
      key || Lightning.Config.token_signer().jwk,
      claims,
      %{"alg" => "RS256", "typ" => typ}
    )
  end

  defp claims(account, overrides \\ %{}) do
    Map.merge(
      %{
        "iss" => AccessToken.issuer(),
        "aud" => AccessToken.issuer() <> "/api",
        "sub" => account.id,
        "scope" => "users:read",
        "exp" => System.system_time(:second) + 300
      },
      overrides
    )
  end

  test "an access token for a service account that is no longer registered is refused without saying whether it expired",
       %{conn: conn, account: account} do
    {replacement, _private_key} = service_account_with_key()

    for token <- [
          AccessToken.issue(account, ["users:read"]),
          expired_access_token(account, "users:read")
        ],
        registered <- [replacement, nil] do
      Mox.stub(Lightning.MockConfig, :service_account, fn -> registered end)

      conn |> get_users(token) |> assert_refused()
    end
  end

  describe "a token only a forger could send, on GET /api/users" do
    test "with no scope claim logs in holding no grants", %{
      conn: conn,
      account: account
    } do
      token = signed_access_token(Map.delete(claims(account), "scope"))

      assert_refused_for_scope(get_users(conn, token), "users:read")
    end

    test "that is right in every way but its typ is refused", %{
      conn: conn,
      account: account
    } do
      token = signed_access_token(claims(account), "JWT")

      conn |> get_users(token) |> assert_refused()
    end

    test "signed with another key is refused", %{conn: conn, account: account} do
      {_, other_key} = service_account_with_key()
      token = signed_access_token(claims(account), "at+jwt", other_key)

      conn |> get_users(token) |> assert_refused()
    end

    test "expired and signed with another key is refused without saying it expired",
         %{conn: conn, account: account} do
      {_, other_key} = service_account_with_key()

      token =
        signed_access_token(
          claims(account, %{"exp" => System.system_time(:second) - 1}),
          "at+jwt",
          other_key
        )

      conn |> get_users(token) |> assert_refused()
    end
  end

  describe "GET /api/projects/:id" do
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

    test "refuses a non-member's personal access token with 403", %{
      conn: conn
    } do
      user = insert(:user)
      project = insert(:project)

      conn =
        conn
        |> with_token(Lightning.Accounts.generate_api_token(user))
        |> get(~p"/api/projects/#{project.id}")

      assert_problem(conn, 403, :forbidden, [])
      assert get_resp_header(conn, "www-authenticate") == []
    end
  end
end
