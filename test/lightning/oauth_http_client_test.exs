defmodule Lightning.AuthProviders.OauthHTTPClientTest do
  use ExUnit.Case, async: true

  import Mox

  alias Lightning.AuthProviders.OauthHTTPClient

  setup :verify_on_exit!

  describe "fetch_token/2" do
    test "fetches token successfully" do
      client = %{
        client_id: "id",
        client_secret: "secret",
        token_endpoint: "http://example.com/token"
      }

      code = "authcode123"

      response_body = %{
        "access_token" => "token123",
        "token_type" => "bearer",
        "refresh_token" => "refresh_token123",
        "expires_in" => 3600
      }

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        %{method: :post, url: "http://example.com/token"} = env, _opts ->
          assert env.body =~ "client_id=id"
          assert env.body =~ "client_secret=secret"
          assert env.body =~ "code=authcode123"
          assert env.body =~ "grant_type=authorization_code"
          assert env.body =~ "redirect_uri="

          {:ok, %Tesla.Env{env | status: 200, body: response_body}}
      end)

      assert {:ok, ^response_body} = OauthHTTPClient.fetch_token(client, code)
    end

    test "fetches token with introspection endpoint" do
      client = %{
        client_id: "id",
        client_secret: "secret",
        token_endpoint: "http://example.com/token",
        introspection_endpoint: "http://example.com/introspect"
      }

      code = "authcode123"

      token_response = %{
        "access_token" => "token123",
        "token_type" => "bearer",
        "refresh_token" => "refresh_token123"
      }

      introspection_response = %{
        "active" => true,
        "exp" => 1_234_567_890
      }

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, 2, fn
        %{method: :post, url: "http://example.com/token"} = env, _opts ->
          {:ok, %Tesla.Env{env | status: 200, body: token_response}}

        %{method: :post, url: "http://example.com/introspect"} = env, _opts ->
          assert env.body =~ "token=token123"
          assert env.body =~ "client_id=id"
          assert env.body =~ "client_secret=secret"
          assert env.body =~ "token_type_hint=access_token"

          {:ok, %Tesla.Env{env | status: 200, body: introspection_response}}
      end)

      expected_token = Map.put(token_response, "expires_at", 1_234_567_890)
      assert {:ok, ^expected_token} = OauthHTTPClient.fetch_token(client, code)
    end

    test "handles token fetch error" do
      client = %{
        client_id: "id",
        client_secret: "secret",
        token_endpoint: "http://example.com/token"
      }

      error_response = %{
        "error" => "invalid_grant",
        "error_description" => "The authorization code is invalid"
      }

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        %{method: :post, url: "http://example.com/token"} = env, _opts ->
          {:ok, %Tesla.Env{env | status: 400, body: error_response}}
      end)

      assert {:error, %{status: 400, error: "invalid_grant", details: details}} =
               OauthHTTPClient.fetch_token(client, "invalid_code")

      assert details.description == "The authorization code is invalid"
    end

    test "handles network error" do
      client = %{
        client_id: "id",
        client_secret: "secret",
        token_endpoint: "http://example.com/token"
      }

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        %{method: :post, url: "http://example.com/token"}, _opts ->
          {:error, %Tesla.Error{reason: :econnrefused}}
      end)

      assert {:error,
              %{
                status: 0,
                error: "network_error",
                details: %{reason: ":econnrefused"}
              }} =
               OauthHTTPClient.fetch_token(client, "code")
    end
  end

  describe "refresh_token/2" do
    test "refreshes token successfully and preserves refresh_token" do
      client = %{
        client_id: "id",
        client_secret: "secret",
        token_endpoint: "http://example.com/token"
      }

      old_token = %{
        "refresh_token" => "refresh123",
        "access_token" => "oldToken123"
      }

      response_body = %{
        "access_token" => "newToken123",
        "token_type" => "bearer",
        "expires_in" => 3600
      }

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        %{method: :post, url: "http://example.com/token"} = env, _opts ->
          assert env.body =~ "grant_type=refresh_token"
          assert env.body =~ "refresh_token=refresh123"

          {:ok, %Tesla.Env{env | status: 200, body: response_body}}
      end)

      assert {:ok, new_token} = OauthHTTPClient.refresh_token(client, old_token)

      assert new_token["refresh_token"] == "refresh123"
      assert new_token["access_token"] == "newToken123"
      assert new_token["updated_at"]
    end

    test "refreshes token with new refresh_token in response" do
      client = %{
        client_id: "id",
        client_secret: "secret",
        token_endpoint: "http://example.com/token"
      }

      old_token = %{
        "refresh_token" => "old_refresh",
        "access_token" => "oldToken"
      }

      response_body = %{
        "access_token" => "newToken",
        "refresh_token" => "new_refresh",
        "token_type" => "bearer"
      }

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        %{method: :post, url: "http://example.com/token"} = env, _opts ->
          {:ok, %Tesla.Env{env | status: 200, body: response_body}}
      end)

      assert {:ok, new_token} = OauthHTTPClient.refresh_token(client, old_token)
      assert new_token["refresh_token"] == "new_refresh"
      assert new_token["updated_at"]
    end

    test "handles missing refresh_token" do
      client = %{
        client_id: "id",
        client_secret: "secret",
        token_endpoint: "http://example.com/token"
      }

      assert {:error,
              %{
                status: 400,
                error: "invalid_request",
                details: %{message: "refresh_token is required"}
              }} =
               OauthHTTPClient.refresh_token(client, %{})

      assert {:error,
              %{
                status: 400,
                error: "invalid_request",
                details: %{message: "refresh_token is required"}
              }} =
               OauthHTTPClient.refresh_token(client, %{"refresh_token" => ""})
    end

    test "handles refresh token error" do
      client = %{
        client_id: "id",
        client_secret: "secret",
        token_endpoint: "http://example.com/token"
      }

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        %{method: :post, url: "http://example.com/token"} = env, _opts ->
          {:ok,
           %Tesla.Env{env | status: 401, body: %{"error" => "invalid_token"}}}
      end)

      assert {:error,
              %{status: 401, error: "invalid_token", details: %{status: 401}}} =
               OauthHTTPClient.refresh_token(client, %{
                 "refresh_token" => "invalid"
               })
    end
  end

  describe "fetch_userinfo/2" do
    test "fetches user information successfully" do
      client = %{
        userinfo_endpoint: "http://example.com/userinfo"
      }

      token = %{"access_token" => "validToken"}
      response_body = %{"user_id" => "123", "name" => "Sadio Mane"}

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        %{method: :get, url: "http://example.com/userinfo", headers: headers} =
            env,
        _opts ->
          assert {"Authorization", "Bearer validToken"} in headers
          {:ok, %Tesla.Env{env | status: 200, body: response_body}}
      end)

      assert {:ok, ^response_body} =
               OauthHTTPClient.fetch_userinfo(client, token)
    end

    test "handles missing access_token" do
      client = %{
        userinfo_endpoint: "http://example.com/userinfo"
      }

      assert {:error,
              %{
                status: 400,
                error: "invalid_request",
                details: %{message: "access_token is required"}
              }} =
               OauthHTTPClient.fetch_userinfo(client, %{})

      assert {:error,
              %{
                status: 400,
                error: "invalid_request",
                details: %{message: "access_token is required"}
              }} =
               OauthHTTPClient.fetch_userinfo(client, %{"access_token" => ""})
    end

    test "handles userinfo fetch error" do
      client = %{
        userinfo_endpoint: "http://example.com/userinfo"
      }

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        %{method: :get, url: "http://example.com/userinfo"} = env, _opts ->
          {:ok, %Tesla.Env{env | status: 401, body: "Unauthorized"}}
      end)

      assert {:error, %{status: 401, error: "http_error", details: details}} =
               OauthHTTPClient.fetch_userinfo(client, %{
                 "access_token" => "expired"
               })

      assert details.status == 401
      assert details.raw_response =~ "Unauthorized"
    end
  end

  describe "revoke_token/2" do
    test "revokes both tokens successfully" do
      client = %{
        client_id: "id",
        client_secret: "secret",
        revocation_endpoint: "http://example.com/revoke"
      }

      token = %{
        "access_token" => "access123",
        "refresh_token" => "refresh123"
      }

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, 2, fn
        %{method: :post, url: "http://example.com/revoke", body: body} = env,
        _opts ->
          cond do
            body =~ "token=refresh123" ->
              assert body =~ "token_type_hint=refresh_token"
              {:ok, %Tesla.Env{env | status: 200, body: ""}}

            body =~ "token=access123" ->
              assert body =~ "token_type_hint=access_token"
              {:ok, %Tesla.Env{env | status: 200, body: ""}}
          end
      end)

      assert :ok = OauthHTTPClient.revoke_token(client, token)
    end

    test "returns ok if at least one token revocation succeeds" do
      client = %{
        client_id: "id",
        client_secret: "secret",
        revocation_endpoint: "http://example.com/revoke"
      }

      token = %{
        "access_token" => "access123",
        "refresh_token" => "refresh123"
      }

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, 2, fn
        %{method: :post, url: "http://example.com/revoke", body: body} = env,
        _opts ->
          cond do
            body =~ "token=refresh123" ->
              {:ok, %Tesla.Env{env | status: 400, body: "Invalid token"}}

            body =~ "token=access123" ->
              {:ok, %Tesla.Env{env | status: 200, body: ""}}
          end
      end)

      assert :ok = OauthHTTPClient.revoke_token(client, token)
    end

    test "handles no tokens to revoke" do
      client = %{
        client_id: "id",
        client_secret: "secret",
        revocation_endpoint: "http://example.com/revoke"
      }

      assert {:error,
              %{
                status: 400,
                error: "no_tokens_to_revoke",
                details: %{message: "No valid tokens found for revocation"}
              }} =
               OauthHTTPClient.revoke_token(client, %{})
    end

    test "returns error if all revocations fail" do
      client = %{
        client_id: "id",
        client_secret: "secret",
        revocation_endpoint: "http://example.com/revoke"
      }

      token = %{
        "access_token" => "access123",
        "refresh_token" => "refresh123"
      }

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, 2, fn
        %{method: :post, url: "http://example.com/revoke"} = env, _opts ->
          {:ok, %Tesla.Env{env | status: 500, body: "Server error"}}
      end)

      assert {:error, %{status: 500, error: "oauth_error", details: details}} =
               OauthHTTPClient.revoke_token(client, token)

      assert Map.has_key?(details, "Server error")
      assert details.status == 500
    end
  end

  describe "generate_authorize_url/2" do
    test "generates authorization URL with default parameters" do
      client = %{
        client_id: "client123",
        authorization_endpoint: "http://example.com/auth"
      }

      url = OauthHTTPClient.generate_authorize_url(client, [])

      assert url =~ "http://example.com/auth?"
      assert url =~ "client_id=client123"
      assert url =~ "response_type=code"
      assert url =~ "access_type=offline"
      assert url =~ "redirect_uri="
    end

    test "generates authorization URL with custom parameters" do
      client = %{
        client_id: "client123",
        authorization_endpoint: "http://example.com/auth"
      }

      custom_params = [
        scope: "email profile",
        state: "xyz123",
        prompt: "consent"
      ]

      url = OauthHTTPClient.generate_authorize_url(client, custom_params)

      assert url =~ "scope=email+profile"
      assert url =~ "state=xyz123"
      assert url =~ "prompt=consent"
    end

    test "custom parameters override defaults" do
      client = %{
        client_id: "client123",
        authorization_endpoint: "http://example.com/auth"
      }

      url =
        OauthHTTPClient.generate_authorize_url(client, response_type: "token")

      assert url =~ "response_type=token"
      refute url =~ "response_type=code"
    end
  end

  describe "error handling" do
    test "handles non-JSON error response" do
      client = %{
        client_id: "id",
        client_secret: "secret",
        token_endpoint: "http://example.com/token"
      }

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        %{method: :post, url: "http://example.com/token"} = env, _opts ->
          {:ok, %Tesla.Env{env | status: 500, body: "Internal Server Error"}}
      end)

      assert {:error, %{status: 500, error: "oauth_error", details: details}} =
               OauthHTTPClient.fetch_token(client, "code")

      assert Map.has_key?(details, "Internal Server Error")
      assert details.status == 500
    end

    test "handles empty response body" do
      client = %{
        userinfo_endpoint: "http://example.com/userinfo"
      }

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        %{method: :get, url: "http://example.com/userinfo"} = env, _opts ->
          {:ok, %Tesla.Env{env | status: 200, body: ""}}
      end)

      assert {:ok, %{}} =
               OauthHTTPClient.fetch_userinfo(client, %{
                 "access_token" => "token"
               })
    end

    test "handles introspection failure gracefully" do
      client = %{
        client_id: "id",
        client_secret: "secret",
        token_endpoint: "http://example.com/token",
        introspection_endpoint: "http://example.com/introspect"
      }

      token_response = %{
        "access_token" => "token123",
        "refresh_token" => "refresh123"
      }

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, 2, fn
        %{method: :post, url: "http://example.com/token"} = env, _opts ->
          {:ok, %Tesla.Env{env | status: 200, body: token_response}}

        %{method: :post, url: "http://example.com/introspect"} = env, _opts ->
          {:ok, %Tesla.Env{env | status: 500, body: "Server Error"}}
      end)

      assert {:ok, ^token_response} = OauthHTTPClient.fetch_token(client, "code")
    end
  end
end
