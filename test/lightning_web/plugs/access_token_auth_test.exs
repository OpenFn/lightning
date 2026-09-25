defmodule LightningWeb.Plugs.AccessTokenAuthTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import Lightning.ServiceAccountHelpers

  alias Lightning.ServiceAccount.AccessToken
  alias LightningWeb.Plugs.AccessTokenAuth

  setup do
    {account, _private_key} = service_account_with_key()
    %{account: account}
  end

  defp authenticate(conn, token) do
    conn
    |> put_req_header("authorization", "Bearer " <> token)
    |> AccessTokenAuth.call(AccessTokenAuth.init([]))
  end

  defp assert_refused(conn, status, error) do
    assert conn.halted
    assert json_response(conn, status) == %{"error" => error}

    assert get_resp_header(conn, "www-authenticate") == [
             ~s(Bearer error="#{error}")
           ]
  end

  describe "call/2" do
    test "lets an access token through with its claims", %{
      conn: conn,
      account: account
    } do
      conn = authenticate(conn, AccessToken.issue(account, ["users:read"]))

      refute conn.halted

      assert %{"sub" => sub, "scope" => "users:read"} =
               conn.assigns.access_token

      assert sub == account.id
    end

    test "refuses a missing token", %{conn: conn} do
      conn |> AccessTokenAuth.call([]) |> assert_refused(401, "invalid_token")
    end

    test "refuses a personal access token", %{conn: conn} do
      token = insert(:user) |> Lightning.Accounts.generate_api_token()

      conn |> authenticate(token) |> assert_refused(401, "invalid_token")
    end

    test "refuses a run token", %{conn: conn} do
      token =
        Lightning.Workers.generate_run_token(%Lightning.Run{
          id: Ecto.UUID.generate()
        })

      conn |> authenticate(token) |> assert_refused(401, "invalid_token")
    end

    test "refuses an expired access token", %{conn: conn, account: account} do
      signer = Lightning.Config.token_signer()
      now = System.system_time(:second)

      {_, token} =
        signer.jwk
        |> JOSE.JWT.sign(%{"alg" => "RS256", "typ" => "at+jwt"}, %{
          "iss" => AccessToken.issuer(),
          "aud" => AccessToken.issuer() <> "/api",
          "sub" => account.id,
          "scope" => "users:read",
          "exp" => now - 1
        })
        |> JOSE.JWS.compact()

      conn |> authenticate(token) |> assert_refused(401, "invalid_token")
    end

    test "refuses a token that is right in every way but its typ", %{
      conn: conn,
      account: account
    } do
      {_, token} =
        Lightning.Config.token_signer().jwk
        |> JOSE.JWT.sign(%{"alg" => "RS256", "typ" => "JWT"}, %{
          "iss" => AccessToken.issuer(),
          "aud" => AccessToken.issuer() <> "/api",
          "sub" => account.id,
          "scope" => "users:read",
          "exp" => System.system_time(:second) + 300
        })
        |> JOSE.JWS.compact()

      conn |> authenticate(token) |> assert_refused(401, "invalid_token")
    end

    test "refuses an at+jwt signed with another key", %{
      conn: conn,
      account: account
    } do
      {_, other_key} = service_account_with_key()

      token =
        sign_assertion(
          other_key,
          %{
            "iss" => AccessToken.issuer(),
            "aud" => AccessToken.issuer() <> "/api",
            "sub" => account.id,
            "scope" => "users:read",
            "exp" => System.system_time(:second) + 300
          },
          %{"alg" => "RS256", "typ" => "at+jwt"}
        )

      conn |> authenticate(token) |> assert_refused(401, "invalid_token")
    end
  end

  describe "require_scope/2" do
    test "lets a token with the scope through", %{conn: conn, account: account} do
      conn =
        conn
        |> authenticate(AccessToken.issue(account, ["users:read"]))
        |> AccessTokenAuth.require_scope("users:read")

      refute conn.halted
    end

    test "refuses a token without the scope", %{conn: conn, account: account} do
      conn
      |> authenticate(AccessToken.issue(account, ["users:read"]))
      |> AccessTokenAuth.require_scope("users:write")
      |> assert_refused(403, "insufficient_scope")
    end
  end

  test "the existing /api routes refuse an access token", %{
    conn: conn,
    account: account
  } do
    token = AccessToken.issue(account, AccessToken.scopes())

    conn =
      conn
      |> put_req_header("authorization", "Bearer " <> token)
      |> get(~p"/api/projects")

    assert json_response(conn, 401)
  end
end
