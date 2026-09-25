defmodule LightningWeb.TokenExchangeControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.ServiceAccountHelpers

  @assertion_type "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

  setup do
    {account, private_key} = service_account_with_key()
    Mox.stub(Lightning.MockConfig, :service_account, fn -> account end)
    %{account: account, private_key: private_key}
  end

  defp token_endpoint(conn) do
    conn
    |> get("/.well-known/oauth-authorization-server")
    |> json_response(200)
    |> Map.fetch!("token_endpoint")
  end

  defp exchange(conn, params) do
    conn
    |> put_req_header("content-type", "application/x-www-form-urlencoded")
    |> post("/api/oauth/token", URI.encode_query(params))
  end

  defp valid_params(account, private_key, audience, extra \\ %{}) do
    Map.merge(
      %{
        "grant_type" => "client_credentials",
        "client_assertion_type" => @assertion_type,
        "client_assertion" =>
          sign_assertion(private_key, assertion_claims(account, audience))
      },
      extra
    )
  end

  describe "GET /.well-known/oauth-authorization-server" do
    test "describes the exchange, with a token endpoint that is the route", %{
      conn: conn
    } do
      base = LightningWeb.Endpoint.url()

      assert json_response(
               get(conn, "/.well-known/oauth-authorization-server"),
               200
             ) == %{
               "issuer" => base,
               "token_endpoint" => base <> "/api/oauth/token",
               "grant_types_supported" => ["client_credentials"],
               "token_endpoint_auth_methods_supported" => ["private_key_jwt"],
               "token_endpoint_auth_signing_alg_values_supported" => ["RS256"],
               "scopes_supported" => ["users:read", "users:write"],
               "response_types_supported" => []
             }

      assert %URI{path: path} = URI.parse(token_endpoint(conn))

      assert %{plug: LightningWeb.TokenExchangeController, plug_opts: :token} =
               Phoenix.Router.route_info(LightningWeb.Router, "POST", path, "")
    end
  end

  describe "POST /api/oauth/token" do
    test "trades a valid assertion for a five-minute access token", %{
      conn: conn,
      account: account,
      private_key: private_key
    } do
      conn =
        exchange(conn, valid_params(account, private_key, token_endpoint(conn)))

      assert %{
               "access_token" => access_token,
               "token_type" => "Bearer",
               "expires_in" => 300,
               "scope" => "users:read users:write"
             } = json_response(conn, 200)

      assert get_resp_header(conn, "cache-control") == ["no-store"]

      signer = Lightning.Config.token_signer()

      assert {true, %JOSE.JWT{fields: claims}, %JOSE.JWS{fields: header}} =
               JOSE.JWT.verify_strict(signer.jwk, ["RS256"], access_token)

      assert header["typ"] == "at+jwt"

      base = LightningWeb.Endpoint.url()

      assert %{
               "iss" => ^base,
               "aud" => aud,
               "sub" => sub,
               "client_id" => sub,
               "scope" => "users:read users:write",
               "iat" => iat,
               "exp" => exp,
               "jti" => jti
             } = claims

      assert sub == account.id
      assert aud == base <> "/api"
      assert exp - iat == 300
      assert is_binary(jti)
    end

    test "grants only the scope asked for", %{
      conn: conn,
      account: account,
      private_key: private_key
    } do
      params =
        valid_params(account, private_key, token_endpoint(conn), %{
          "scope" => "users:read"
        })

      assert %{"scope" => "users:read"} =
               conn |> exchange(params) |> json_response(200)
    end

    test "refuses a scope it does not know with invalid_scope", %{
      conn: conn,
      account: account,
      private_key: private_key
    } do
      params =
        valid_params(account, private_key, token_endpoint(conn), %{
          "scope" => "users:read projects:delete"
        })

      assert %{"error" => "invalid_scope"} =
               conn |> exchange(params) |> json_response(400)
    end

    test "refuses a failed assertion with invalid_client", %{
      conn: conn,
      account: account,
      private_key: private_key
    } do
      params = valid_params(account, private_key, token_endpoint(conn))

      assert %{"access_token" => _} =
               conn |> exchange(params) |> json_response(200)

      assert conn |> exchange(params) |> json_response(401) == %{
               "error" => "invalid_client"
             }

      params = valid_params(account, private_key, "https://elsewhere.example")

      assert %{"error" => "invalid_client"} =
               conn |> exchange(params) |> json_response(401)
    end

    test "refuses a client_id that is not the assertion's issuer", %{
      conn: conn,
      account: account,
      private_key: private_key
    } do
      params =
        valid_params(account, private_key, token_endpoint(conn), %{
          "client_id" => "someone-else"
        })

      assert %{"error" => "invalid_client"} =
               conn |> exchange(params) |> json_response(401)
    end

    test "refuses another grant type with unsupported_grant_type", %{
      conn: conn,
      account: account,
      private_key: private_key
    } do
      params =
        valid_params(account, private_key, token_endpoint(conn), %{
          "grant_type" => "urn:ietf:params:oauth:grant-type:jwt-bearer"
        })

      assert %{"error" => "unsupported_grant_type"} =
               conn |> exchange(params) |> json_response(400)
    end

    test "refuses a malformed request with invalid_request", %{
      conn: conn,
      account: account,
      private_key: private_key
    } do
      params = valid_params(account, private_key, token_endpoint(conn))

      for broken <- [
            Map.delete(params, "grant_type"),
            Map.delete(params, "client_assertion"),
            Map.put(params, "client_assertion_type", "something-else")
          ] do
        assert %{"error" => "invalid_request"} =
                 conn |> exchange(broken) |> json_response(400)
      end

      assert %{"error" => "invalid_request"} =
               conn
               |> put_req_header(
                 "content-type",
                 "application/x-www-form-urlencoded"
               )
               |> post("/api/oauth/token?" <> URI.encode_query(params), "")
               |> json_response(400)

      assert %{"error" => "invalid_request"} =
               conn
               |> put_req_header("content-type", "application/json")
               |> post("/api/oauth/token", Jason.encode!(params))
               |> json_response(400)
    end
  end
end
