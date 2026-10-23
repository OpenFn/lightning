defmodule LightningWeb.Plugs.AccessTokenAuthTest do
  use LightningWeb.ConnCase, async: true

  import LightningWeb.API.ProblemHelpers
  import Lightning.ServiceAccountHelpers

  alias Lightning.ServiceAccount.AccessToken
  alias LightningWeb.Plugs.AccessTokenAuth

  setup do
    {account, _private_key} = service_account_with_key()
    Mox.stub(Lightning.MockConfig, :service_account, fn -> account end)
    %{account: account}
  end

  defp authenticate(conn, token) do
    conn
    |> put_req_header("authorization", "Bearer " <> token)
    |> AccessTokenAuth.call(AccessTokenAuth.init([]))
  end

  defp get_users(conn, token) do
    conn
    |> put_req_header("accept", "application/json")
    |> put_req_header("authorization", "Bearer " <> token)
    |> get(~p"/api/users")
  end

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

  test "lets an access token through with its claims and service account",
       %{conn: conn, account: account} do
    conn =
      authenticate(
        conn,
        AccessToken.issue(account, ["users:read", "projects:write"])
      )

    refute conn.halted

    assert %{"sub" => sub, "scope" => "users:read projects:write"} =
             conn.assigns.access_token

    assert sub == account.id

    assert conn.assigns.current_resource == %{
             account
             | grants: MapSet.new(["users:read", "projects:write"])
           }
  end

  describe "a token only a forger could send, on GET /api/users" do
    test "with no scope claim logs in holding no grants", %{
      conn: conn,
      account: account
    } do
      token = signed_access_token(Map.delete(claims(account), "scope"))

      assert_refused_for_scope(get_users(conn, token), "users:read")
    end

    test "for a service account that is no longer registered is refused", %{
      conn: conn,
      account: account
    } do
      token = AccessToken.issue(account, ["users:read"])
      {replacement, _private_key} = service_account_with_key()
      Mox.stub(Lightning.MockConfig, :service_account, fn -> replacement end)

      conn |> get_users(token) |> assert_refused()

      Mox.stub(Lightning.MockConfig, :service_account, fn -> nil end)

      conn |> get_users(token) |> assert_refused()
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
  end
end
