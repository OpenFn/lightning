defmodule Lightning.AuthProviders.OauthHTTPClientTest do
  use ExUnit.Case, async: true
  import Mox

  setup :verify_on_exit!

  describe "fetch_token/2" do
    test "fetches token successfully" do
      client = %{
        client_id: "id",
        client_secret: "secret",
        token_endpoint: "http://example.com/token"
      }

      code = "authcode123"
      response_body = %{"access_token" => "token123", "token_type" => "bearer"}

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        env, _opts
        when env.method == :post and env.url == "http://example.com/token" ->
          assert env.body ==
                   %{
                     client_id: "id",
                     client_secret: "secret",
                     code: "authcode123",
                     grant_type: "authorization_code",
                     redirect_uri: "http://localhost:4002/authenticate/callback"
                   }
                   |> URI.encode_query()

          {:ok, %Tesla.Env{status: 200, body: Jason.encode!(response_body)}}
      end)

      result =
        Lightning.AuthProviders.OauthHTTPClient.fetch_token(client, code)

      assert {:ok, response_body} == result
    end
  end

  describe "refresh_token/4" do
    test "refreshes the token successfully" do
      client_id = "id"
      client_secret = "secret"
      refresh_token = "validRefreshToken"
      token_endpoint = "http://example.com/refresh"

      response_body = %{
        "access_token" => "newToken123",
        "token_type" => "bearer"
      }

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        env, _opts
        when env.method == :post and env.url == token_endpoint ->
          assert env.body ==
                   %{
                     client_id: client_id,
                     client_secret: client_secret,
                     refresh_token: refresh_token,
                     grant_type: "refresh_token"
                   }
                   |> URI.encode_query()

          {:ok, %Tesla.Env{status: 200, body: Jason.encode!(response_body)}}
      end)

      result =
        Lightning.AuthProviders.OauthHTTPClient.refresh_token(
          client_id,
          client_secret,
          refresh_token,
          token_endpoint
        )

      assert {:ok, response_body} == result
    end

    test "handles error when refresh token is invalid" do
      client_id = "id"
      client_secret = "secret"
      refresh_token = "invalidRefreshToken"
      token_endpoint = "http://example.com/refresh"

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        env, _opts
        when env.method == :post and env.url == token_endpoint ->
          {:ok, %Tesla.Env{status: 400, body: "Invalid refresh token"}}
      end)

      result =
        Lightning.AuthProviders.OauthHTTPClient.refresh_token(
          client_id,
          client_secret,
          refresh_token,
          token_endpoint
        )

      assert {:error, "Failed to fetch user info: \"Invalid refresh token\""} ==
               result
    end
  end

  describe "fetch_userinfo/2" do
    test "fetches user information successfully" do
      token = "validAccessToken"
      userinfo_endpoint = "http://example.com/userinfo"
      response_body = %{"user_id" => "123", "name" => "John Doe"}

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        env, _opts
        when env.method == :get and env.url == userinfo_endpoint ->
          assert Enum.any?(env.headers, fn {k, v} ->
                   k == "Authorization" and v == "Bearer #{token}"
                 end)

          {:ok, %Tesla.Env{status: 200, body: Jason.encode!(response_body)}}
      end)

      result =
        Lightning.AuthProviders.OauthHTTPClient.fetch_userinfo(
          token,
          userinfo_endpoint
        )

      assert {:ok, response_body} == result
    end

    test "handles error when access token is expired" do
      token = "expiredAccessToken"
      userinfo_endpoint = "http://example.com/userinfo"

      expect(Lightning.AuthProviders.OauthHTTPClient.Mock, :call, fn
        env, _opts
        when env.method == :get and env.url == userinfo_endpoint ->
          {:ok, %Tesla.Env{status: 401, body: "Token expired"}}
      end)

      result =
        Lightning.AuthProviders.OauthHTTPClient.fetch_userinfo(
          token,
          userinfo_endpoint
        )

      assert {:error, "Failed to fetch user info: \"Token expired\""} == result
    end
  end
end
