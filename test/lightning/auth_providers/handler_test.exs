defmodule Lightning.AuthProviders.HandlerTest do
  use ExUnit.Case, async: true

  import Lightning.BypassHelpers

  alias Lightning.AuthProviders.Handler
  alias Lightning.AuthProviders.WellKnown

  @client_id "client-abc"
  @nonce "the-expected-nonce"

  setup do
    bypass = Bypass.open()

    # Bypass can reuse a port across tests; evict only this port's cached JWKS
    # (not the whole cache, which concurrent async tests share) so a prior test's
    # keys can't be served for this test's same-port jwks_uri.
    Cachex.del(:auth_provider_jwks, "#{endpoint_url(bypass)}/jwks")

    wellknown = %WellKnown{
      authorization_endpoint: "#{endpoint_url(bypass)}/authorization_endpoint",
      token_endpoint: "#{endpoint_url(bypass)}/token_endpoint",
      userinfo_endpoint: "#{endpoint_url(bypass)}/userinfo_endpoint",
      jwks_uri: "#{endpoint_url(bypass)}/jwks",
      issuer: endpoint_url(bypass)
    }

    {:ok, handler} =
      Handler.new("handler-#{System.unique_integer([:positive])}",
        wellknown: wellknown,
        client_id: @client_id,
        client_secret: "secret",
        redirect_uri: "http://localhost/callback_url"
      )

    {:ok, handler: handler, bypass: bypass}
  end

  describe "verify_id_token/3" do
    test "returns the claims for a valid id_token", %{
      handler: handler,
      bypass: bypass
    } do
      expect_jwks(bypass, handler.wellknown.jwks_uri)

      claims = valid_claims(handler)
      token = token_with_id(sign_id_token(claims))

      assert {:ok, verified} = Handler.verify_id_token(handler, token, @nonce)

      assert %{
               "iss" => _,
               "aud" => @client_id,
               "nonce" => @nonce,
               "email" => "person@example.com",
               "email_verified" => true
             } = verified
    end

    test "rejects a token missing an id_token", %{handler: handler} do
      token = %OAuth2.AccessToken{other_params: %{}}

      assert {:error, :missing_id_token} =
               Handler.verify_id_token(handler, token, @nonce)
    end

    test "rejects an id_token signed with the wrong key", %{
      handler: handler,
      bypass: bypass
    } do
      expect_jwks(bypass, handler.wellknown.jwks_uri)

      claims = valid_claims(handler)
      # Forged with a different key, but the header kid still points at the
      # served (correct) public key, so only the signature check can fail.
      token =
        token_with_id(sign_id_token(claims, other_private_jwk(), test_kid()))

      assert {:error, :invalid_signature} =
               Handler.verify_id_token(handler, token, @nonce)
    end

    test "rejects an unsecured id_token (alg \"none\")", %{
      handler: handler,
      bypass: bypass
    } do
      expect_jwks(bypass, handler.wellknown.jwks_uri)

      # An attacker-forged unsecured token: valid claims, empty signature, header
      # alg "none". The asymmetric-only allowlist must refuse it rather than
      # trust an unsigned payload.
      token = token_with_id(unsecured_id_token(valid_claims(handler)))

      assert {:error, :invalid_signature} =
               Handler.verify_id_token(handler, token, @nonce)
    end

    test "rejects an HS256 id_token forged with the RSA public key (alg confusion)",
         %{handler: handler, bypass: bypass} do
      expect_jwks(bypass, handler.wellknown.jwks_uri)

      # The classic alg-confusion attack: HMAC-sign the token using the
      # provider's RSA *public* key as the shared secret and claim alg HS256. A
      # verifier that doesn't pin asymmetric algs would treat the public key as
      # an HMAC secret and accept the forgery; the allowlist must reject it.
      token = token_with_id(hs256_forged_id_token(valid_claims(handler)))

      assert {:error, :invalid_signature} =
               Handler.verify_id_token(handler, token, @nonce)
    end

    test "rejects an id_token with the wrong issuer", %{
      handler: handler,
      bypass: bypass
    } do
      expect_jwks(bypass, handler.wellknown.jwks_uri)

      claims = valid_claims(handler, %{"iss" => "https://evil.example.com"})
      token = token_with_id(sign_id_token(claims))

      assert {:error, :invalid_issuer} =
               Handler.verify_id_token(handler, token, @nonce)
    end

    test "rejects an id_token whose audience is not our client", %{
      handler: handler,
      bypass: bypass
    } do
      expect_jwks(bypass, handler.wellknown.jwks_uri)

      claims = valid_claims(handler, %{"aud" => "someone-else"})
      token = token_with_id(sign_id_token(claims))

      assert {:error, :invalid_audience} =
               Handler.verify_id_token(handler, token, @nonce)
    end

    test "rejects a multi-audience id_token without a matching azp", %{
      handler: handler,
      bypass: bypass
    } do
      expect_jwks(bypass, handler.wellknown.jwks_uri)

      claims = valid_claims(handler, %{"aud" => [@client_id, "other-client"]})
      token = token_with_id(sign_id_token(claims))

      assert {:error, :invalid_audience} =
               Handler.verify_id_token(handler, token, @nonce)
    end

    test "accepts a multi-audience id_token when azp names our client", %{
      handler: handler,
      bypass: bypass
    } do
      expect_jwks(bypass, handler.wellknown.jwks_uri)

      claims =
        valid_claims(handler, %{
          "aud" => [@client_id, "other-client"],
          "azp" => @client_id
        })

      token = token_with_id(sign_id_token(claims))

      assert {:ok, _claims} = Handler.verify_id_token(handler, token, @nonce)
    end

    test "rejects an expired id_token", %{handler: handler, bypass: bypass} do
      expect_jwks(bypass, handler.wellknown.jwks_uri)

      claims =
        valid_claims(handler, %{"exp" => System.system_time(:second) - 60})

      token = token_with_id(sign_id_token(claims))

      assert {:error, :expired} =
               Handler.verify_id_token(handler, token, @nonce)
    end

    test "rejects an id_token whose nonce does not match", %{
      handler: handler,
      bypass: bypass
    } do
      expect_jwks(bypass, handler.wellknown.jwks_uri)

      claims = valid_claims(handler, %{"nonce" => "a-different-nonce"})
      token = token_with_id(sign_id_token(claims))

      assert {:error, :invalid_nonce} =
               Handler.verify_id_token(handler, token, @nonce)
    end

    test "rejects when the expected nonce is nil", %{
      handler: handler,
      bypass: bypass
    } do
      expect_jwks(bypass, handler.wellknown.jwks_uri)

      claims = valid_claims(handler)
      token = token_with_id(sign_id_token(claims))

      assert {:error, :missing_nonce} =
               Handler.verify_id_token(handler, token, nil)
    end

    test "fetches the JWKS once and serves subsequent logins from cache", %{
      handler: handler,
      bypass: bypass
    } do
      {:ok, calls} = Agent.start_link(fn -> 0 end)
      path = URI.new!(handler.wellknown.jwks_uri).path

      Bypass.expect(bypass, "GET", path, fn conn ->
        Agent.update(calls, &(&1 + 1))

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(jwks()))
      end)

      token = token_with_id(sign_id_token(valid_claims(handler)))

      assert {:ok, _} = Handler.verify_id_token(handler, token, @nonce)
      assert {:ok, _} = Handler.verify_id_token(handler, token, @nonce)

      assert Agent.get(calls, & &1) == 1
    end

    test "refetches the JWKS when the token's kid is not in the cached set", %{
      handler: handler,
      bypass: bypass
    } do
      {:ok, calls} = Agent.start_link(fn -> 0 end)
      path = URI.new!(handler.wellknown.jwks_uri).path

      # Serve only the original key first; after that, serve a rotated-in key too.
      Bypass.expect(bypass, "GET", path, fn conn ->
        n = Agent.get_and_update(calls, &{&1, &1 + 1})

        keys =
          if n == 0,
            do: [public_jwk_map()],
            else: [public_jwk_map(), other_public_jwk_map("rotated-kid")]

        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.resp(200, Jason.encode!(%{"keys" => keys}))
      end)

      # First login caches the original key set.
      original = token_with_id(sign_id_token(valid_claims(handler)))
      assert {:ok, _} = Handler.verify_id_token(handler, original, @nonce)

      # A token signed by a rotated key with a new kid isn't in the cached set,
      # so it triggers a refetch that picks up the new key.
      rotated =
        token_with_id(
          sign_id_token(
            valid_claims(handler),
            other_private_jwk(),
            "rotated-kid"
          )
        )

      assert {:ok, _} = Handler.verify_id_token(handler, rotated, @nonce)
      assert Agent.get(calls, & &1) == 2
    end

    test "rejects a non-https jwks_uri", %{handler: handler} do
      insecure = %{
        handler
        | wellknown: %{handler.wellknown | jwks_uri: "http://example.com/jwks"}
      }

      token = token_with_id(sign_id_token(valid_claims(handler)))

      assert {:error, :insecure_jwks_uri} =
               Handler.verify_id_token(insecure, token, @nonce)
    end
  end

  describe "new/2" do
    test "builds the token-exchange client with TLS verification opts", %{
      handler: handler
    } do
      # Hackney reads `ssl_options`, so guard against silently regressing the key.
      assert Keyword.has_key?(handler.client.request_opts, :ssl_options)
    end
  end

  describe "get_token/2" do
    test "refuses a plaintext (non-loopback) token endpoint", %{handler: handler} do
      insecure = %{
        handler
        | wellknown: %{
            handler.wellknown
            | token_endpoint: "http://accounts.example.com/token"
          }
      }

      assert {:error, :insecure_token_endpoint} =
               Handler.get_token(insecure, "callback_code")
    end
  end

  describe "get_userinfo/2" do
    test "refuses a plaintext (non-loopback) userinfo endpoint", %{
      handler: handler
    } do
      insecure = %{
        handler
        | wellknown: %{
            handler.wellknown
            | userinfo_endpoint: "http://accounts.example.com/userinfo"
          }
      }

      token = %OAuth2.AccessToken{access_token: "access-token"}

      assert_raise RuntimeError, ~r/unverified/, fn ->
        Handler.get_userinfo(insecure, token)
      end
    end
  end

  defp valid_claims(handler, overrides \\ %{}) do
    Map.merge(
      %{
        "iss" => handler.wellknown.issuer,
        "aud" => @client_id,
        "exp" => System.system_time(:second) + 3600,
        "nonce" => @nonce,
        "sub" => "subject-123",
        "email" => "person@example.com",
        "email_verified" => true
      },
      overrides
    )
  end

  defp token_with_id(id_token),
    do: %OAuth2.AccessToken{other_params: %{"id_token" => id_token}}

  # An unsecured JWT (`alg: none`, empty signature), assembled by hand so we
  # don't have to flip JOSE's global unsecured-signing switch just to forge one.
  defp unsecured_id_token(claims) do
    header =
      %{"alg" => "none", "typ" => "JWT"}
      |> Jason.encode!()
      |> Base.url_encode64(padding: false)

    payload = claims |> Jason.encode!() |> Base.url_encode64(padding: false)

    "#{header}.#{payload}."
  end

  # HMAC-sign the token using the provider's RSA *public* key bytes as the HS256
  # secret and label it `kid: test-signing-key` — the alg-confusion vector.
  defp hs256_forged_id_token(claims) do
    public_secret =
      test_private_jwk()
      |> JOSE.JWK.to_public()
      |> JOSE.JWK.to_pem()
      |> elem(1)

    JOSE.JWK.from_oct(public_secret)
    |> JOSE.JWT.sign(%{"alg" => "HS256", "kid" => test_kid()}, claims)
    |> JOSE.JWS.compact()
    |> elem(1)
  end
end
