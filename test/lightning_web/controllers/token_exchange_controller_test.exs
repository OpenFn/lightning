defmodule LightningWeb.TokenExchangeControllerTest do
  use LightningWeb.ConnCase, async: true

  import ExUnit.CaptureLog
  import Lightning.ServiceAccountHelpers

  alias Lightning.ServiceAccount.Assertion

  @assertion_type "urn:ietf:params:oauth:client-assertion-type:jwt-bearer"

  @unknown_scope "scope names something that is not a token grant. " <>
                   "scopes_supported in /.well-known/oauth-authorization-server " <>
                   "lists them."
  @wrong_client_id "client_id must be the service account id, the same as " <>
                     "the assertion's iss, or be left out."
  @replayed "This assertion's jti has been used before. Sign a new assertion " <>
              "with a new jti for each token request."

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
          sign_assertion(private_key, assertion_claims(account, audience)),
        "scope" => "users:read"
      },
      extra
    )
  end

  # OAuth allows only these characters in an error_description, which leave
  # out double quotes and backslashes.
  defp assert_refused(conn, status, error, description) do
    body = json_response(conn, status)

    assert body == %{"error" => error, "error_description" => description}
    assert get_resp_header(conn, "www-authenticate") == []
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
               "scopes_supported" => [
                 "users:read",
                 "users:write",
                 "projects:write",
                 "credentials:write",
                 "collections:write"
               ],
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
      params =
        valid_params(account, private_key, token_endpoint(conn), %{
          "scope" => "users:read users:write projects:write"
        })

      conn = exchange(conn, params)

      assert %{
               "access_token" => access_token,
               "token_type" => "Bearer",
               "expires_in" => 300,
               "scope" => "users:read users:write projects:write"
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
               "scope" => "users:read users:write projects:write",
               "iat" => iat,
               "exp" => exp,
               "jti" => jti
             } = claims

      assert sub == account.id
      assert aud == base <> "/api"
      assert exp - iat == 300
      assert is_binary(jti)
    end

    test "records each token it issues, and no refusal", %{
      conn: conn,
      account: account,
      private_key: private_key
    } do
      params =
        valid_params(account, private_key, token_endpoint(conn), %{
          "scope" => "users:read"
        })

      assert conn |> exchange(params) |> json_response(200)
      assert conn |> exchange(params) |> json_response(401)

      uuid = account.uuid

      assert %{
               entries: [
                 %{
                   item_type: "service_account",
                   event: "token_issued",
                   item_id: ^uuid,
                   actor_type: :service_account,
                   actor_id: ^uuid,
                   metadata: %{"scopes" => ["users:read"]}
                 } = audit
               ]
             } = Lightning.Auditing.list_all()

      assert audit.actor_display.identifier == account.id
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

    test "accepts the form content type in any letter case and with parameters",
         %{conn: conn, account: account, private_key: private_key} do
      audience = token_endpoint(conn)

      for content_type <- [
            "Application/X-WWW-Form-Urlencoded",
            "application/x-www-form-urlencoded; charset=UTF-8"
          ] do
        params = valid_params(account, private_key, audience)

        assert %{
                 "access_token" => access_token,
                 "token_type" => "Bearer",
                 "scope" => "users:read"
               } =
                 conn
                 |> put_req_header("content-type", content_type)
                 |> post("/api/oauth/token", URI.encode_query(params))
                 |> json_response(200)

        assert is_binary(access_token)
      end
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

      conn
      |> exchange(params)
      |> assert_refused(400, "invalid_scope", @unknown_scope)
    end

    test "refuses projects:provision, which only a repo connection holds", %{
      conn: conn,
      account: account,
      private_key: private_key
    } do
      params =
        valid_params(account, private_key, token_endpoint(conn), %{
          "scope" => "projects:provision"
        })

      conn
      |> exchange(params)
      |> assert_refused(400, "invalid_scope", @unknown_scope)
    end

    test "refuses a request that names no scope with invalid_scope", %{
      conn: conn,
      account: account,
      private_key: private_key
    } do
      params = valid_params(account, private_key, token_endpoint(conn))

      for params <- [
            Map.delete(params, "scope"),
            Map.put(params, "scope", ""),
            Map.put(params, "scope", " ")
          ] do
        conn
        |> exchange(params)
        |> assert_refused(
          400,
          "invalid_scope",
          "scope is missing or empty. Name the token grants you need, " <>
            "separated by spaces."
        )
      end
    end

    test "refuses each kind of bad assertion, saying why", %{
      conn: conn,
      account: account,
      private_key: private_key
    } do
      audience = token_endpoint(conn)
      now = System.system_time(:second)
      {other_account, other_key} = service_account_with_key()

      used = valid_params(account, private_key, audience)

      assert %{"access_token" => _} =
               conn |> exchange(used) |> json_response(200)

      with_assertion = &Map.put(used, "client_assertion", &1)

      signed =
        &with_assertion.(
          sign_assertion(private_key, assertion_claims(account, audience, &1))
        )

      cases = %{
        malformed:
          {with_assertion.("not-a-jwt"),
           "client_assertion is not a JWT with an iss claim."},
        unknown_service_account:
          {with_assertion.(
             sign_assertion(other_key, assertion_claims(other_account, audience))
           ), "The assertion's iss is not this server's service account id."},
        bad_signature:
          {with_assertion.(
             sign_assertion(other_key, assertion_claims(account, audience))
           ),
           "The assertion's signature does not verify with the service " <>
             "account's public key. Sign it with RS256 and the matching " <>
             "private key."},
        wrong_subject:
          {signed.(%{"sub" => "x"}),
           "The assertion's sub must be the service account id, the same as " <>
             "its iss."},
        wrong_audience:
          {signed.(%{"aud" => "https://elsewhere.example"}),
           "The assertion's aud must be exactly the token_endpoint URL in " <>
             "/.well-known/oauth-authorization-server."},
        missing_claims:
          {signed.(%{"jti" => nil}),
           "The assertion needs integer exp and iat claims, and a jti of 1 " <>
             "to 255 bytes with no NUL character."},
        expired:
          {signed.(%{"exp" => now - 1, "iat" => now - 30}),
           "The assertion's exp has passed. Check the client's clock."},
        lives_too_long:
          {signed.(%{"exp" => now + 120, "iat" => now}),
           "The assertion's exp is more than 60 seconds after its iat."},
        issued_in_future:
          {signed.(%{"iat" => now + 30, "exp" => now + 60}),
           "The assertion's iat is more than 5 seconds ahead of the server's " <>
             "clock. Check the client's clock."},
        wrong_client_id:
          {signed.(%{}) |> Map.put("client_id", "someone-else"),
           @wrong_client_id},
        replayed: {used, @replayed}
      }

      for {_reason, {params, description}} <- cases do
        conn
        |> exchange(params)
        |> assert_refused(401, "invalid_client", description)
      end

      assert MapSet.new(Map.keys(cases)) == MapSet.new(Assertion.errors())
    end

    test "gives an iss the same answer whether or not a service account is set up",
         %{conn: conn, account: account, private_key: private_key} do
      Mox.stub(Lightning.MockConfig, :service_account, fn -> nil end)

      conn
      |> exchange(valid_params(account, private_key, token_endpoint(conn)))
      |> assert_refused(
        401,
        "invalid_client",
        "The assertion's iss is not this server's service account id."
      )
    end

    test "leaves an assertion refused for its client_id usable once", %{
      conn: conn,
      account: account,
      private_key: private_key
    } do
      params = valid_params(account, private_key, token_endpoint(conn))

      conn
      |> exchange(Map.put(params, "client_id", "someone-else"))
      |> assert_refused(401, "invalid_client", @wrong_client_id)

      assert %{"access_token" => _} =
               conn
               |> exchange(Map.put(params, "client_id", account.id))
               |> json_response(200)

      conn
      |> exchange(params)
      |> assert_refused(401, "invalid_client", @replayed)
    end

    # No other test module refuses with :wrong_client_id, so no test running
    # alongside this one shares its log bucket.
    test "warns of refusals at most once a minute and counts every one", %{
      conn: conn,
      account: account,
      private_key: private_key
    } do
      Hammer.delete_buckets(
        LightningWeb.TokenExchangeController.refusal_log_bucket(:wrong_client_id)
      )

      ref =
        :telemetry_test.attach_event_handlers(self(), [
          [:lightning, :service_account, :assertion_refused]
        ])

      refuse = fn ->
        params =
          valid_params(account, private_key, token_endpoint(conn), %{
            "client_id" => "someone-else"
          })

        conn |> exchange(params) |> json_response(401)
      end

      assert capture_log([level: :warning], refuse) =~
               "Refused a service account assertion: wrong_client_id"

      refute capture_log([level: :warning], refuse) =~ "wrong_client_id"

      for _ <- 1..2 do
        assert_receive {[:lightning, :service_account, :assertion_refused], ^ref,
                        %{count: 1}, %{reason: :wrong_client_id}}
      end
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

      conn
      |> exchange(params)
      |> assert_refused(
        400,
        "unsupported_grant_type",
        "grant_type must be client_credentials."
      )
    end

    test "refuses a malformed request with invalid_request, saying why", %{
      conn: conn,
      account: account,
      private_key: private_key
    } do
      params = valid_params(account, private_key, token_endpoint(conn))
      form = "application/x-www-form-urlencoded"

      no_grant_type =
        "The body has no single grant_type value. Send " <>
          "grant_type=client_credentials in the form-encoded body, not the " <>
          "query string."

      no_client_assertion =
        "Send client_assertion_type " <>
          "urn:ietf:params:oauth:client-assertion-type:jwt-bearer and the " <>
          "signed JWT in client_assertion."

      not_form_encoded =
        "The body must be form-encoded, as application/x-www-form-urlencoded."

      for {content_type, query, body, description} <- [
            {form, "", Map.delete(params, "grant_type"), no_grant_type},
            {form, "",
             params
             |> Map.delete("grant_type")
             |> Map.put("grant_type[]", "client_credentials"), no_grant_type},
            {form, "?" <> URI.encode_query(params), %{}, no_grant_type},
            {form, "", Map.delete(params, "client_assertion"),
             no_client_assertion},
            {form, "",
             Map.put(params, "client_assertion_type", "something-else"),
             no_client_assertion},
            {form, "",
             params |> Map.delete("scope") |> Map.put("scope[]", "users:read"),
             "scope must be one value, with token grants separated by spaces."},
            {"application/json", "", params, not_form_encoded},
            {form <> "foo", "", params, not_form_encoded}
          ] do
        encode =
          if content_type == "application/json",
            do: &Jason.encode!/1,
            else: &URI.encode_query/1

        conn
        |> put_req_header("content-type", content_type)
        |> post("/api/oauth/token" <> query, encode.(body))
        |> assert_refused(400, "invalid_request", description)
      end
    end
  end
end
