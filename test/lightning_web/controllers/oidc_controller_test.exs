defmodule LightningWeb.OidcControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.BypassHelpers
  import Lightning.AccountsFixtures
  import Lightning.Factories

  alias Lightning.AuthProviders

  def setup_handler(_) do
    bypass = Bypass.open()

    # Bypass can reuse a port across tests; evict only this port's cached JWKS
    # (not the whole cache, which concurrent async tests share) so a prior test's
    # keys can't be served for this test's same-port jwks_uri.
    Cachex.del(:auth_provider_jwks, "#{endpoint_url(bypass)}/jwks")

    wellknown = %AuthProviders.WellKnown{
      authorization_endpoint: "#{endpoint_url(bypass)}/authorization_endpoint",
      token_endpoint: "#{endpoint_url(bypass)}/token_endpoint",
      userinfo_endpoint: "#{endpoint_url(bypass)}/userinfo_endpoint",
      jwks_uri: "#{endpoint_url(bypass)}/jwks",
      issuer: endpoint_url(bypass)
    }

    handler_name = :crypto.strong_rand_bytes(6) |> Base.url_encode64()

    {:ok, handler} =
      AuthProviders.Handler.new(handler_name,
        wellknown: wellknown,
        client_id: "id",
        client_secret: "secret",
        redirect_uri: "http://localhost/callback_url"
      )

    AuthProviders.create_handler(handler)

    on_exit(fn -> AuthProviders.remove_handler(handler) end)

    {:ok, handler: handler, bypass: bypass}
  end

  describe "GET /authenticate/:provider" do
    setup :setup_handler

    test "redirects to provider authorize_url and stores state + nonce", %{
      conn: conn,
      handler: handler
    } do
      conn = conn |> get(Routes.oidc_path(conn, :show, handler.name))

      {state, nonce} = session_state_nonce(conn)

      assert is_binary(state)
      assert is_binary(nonce)

      assert redirected_to(conn) ==
               AuthProviders.Handler.authorize_url(handler, state, nonce)
    end

    test "redirects to / when already logged in", %{conn: conn, handler: handler} do
      user = user_fixture()

      conn =
        conn
        |> log_in_user(user)
        |> get(Routes.oidc_path(conn, :show, handler.name))

      assert redirected_to(conn) == "/projects"
    end

    test "renders a 404 when a provider is missing", %{conn: conn} do
      response = get(conn, Routes.oidc_path(conn, :show, "doesntexist"))

      assert response.resp_body =~ "Not Found"
      assert response.status == 404
    end

    test "redirects to login (not a 500) when the provider can't be built", %{
      conn: conn
    } do
      name = unreachable_provider_name()

      conn = get(conn, Routes.oidc_path(conn, :show, name))

      assert redirected_to(conn) == Routes.user_session_path(conn, :new)
    end
  end

  describe "GET /authenticate/:provider/callback" do
    setup :setup_handler

    test "logs the given person in", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      user = user_fixture()

      conn = run_callback(conn, handler, bypass, email: user.email)

      assert redirected_to(conn) == "/projects"
      assert get_session(conn, :user_token)
    end

    test "logs the person in but marks totp as pending for users wth MFA enabled",
         %{
           conn: conn,
           bypass: bypass,
           handler: handler
         } do
      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))

      conn = run_callback(conn, handler, bypass, email: user.email)

      assert get_session(conn, :user_totp_pending)

      assert redirected_to(conn) ==
               Routes.user_totp_path(conn, :new, user: %{"remember_me" => true})

      # The user is redirected to the TOTP page if they try accessing other pages
      conn = get(conn, "/")
      assert redirected_to(conn) == Routes.user_totp_path(conn, :new)
    end

    test "falls back to userinfo when the id_token carries no email", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      user = user_fixture()

      conn =
        run_callback(conn, handler, bypass,
          drop: ["email"],
          userinfo: %{
            "sub" => "subject-123",
            "email" => user.email,
            "email_verified" => true
          }
        )

      assert redirected_to(conn) == "/projects"
      assert get_session(conn, :user_token)
    end

    test "trusts userinfo's verified flag for the id_token email when userinfo omits its own email",
         %{conn: conn, bypass: bypass, handler: handler} do
      user = user_fixture()

      conn =
        run_callback(conn, handler, bypass,
          email: user.email,
          drop: ["email_verified"],
          userinfo: %{"sub" => "subject-123", "email_verified" => true}
        )

      assert redirected_to(conn) == "/projects"
      assert get_session(conn, :user_token)
    end

    test "accepts userinfo's verified flag when its email matches the id_token's apart from casing",
         %{conn: conn, bypass: bypass, handler: handler} do
      user = user_fixture()

      conn =
        run_callback(conn, handler, bypass,
          email: user.email,
          drop: ["email_verified"],
          userinfo: %{
            "sub" => "subject-123",
            "email" => String.upcase(user.email),
            "email_verified" => true
          }
        )

      assert redirected_to(conn) == "/projects"
      assert get_session(conn, :user_token)
    end

    test "fails closed (no 500) when userinfo returns a non-string email", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      _user = user_fixture()

      conn =
        run_callback(conn, handler, bypass,
          email: "person@example.com",
          drop: ["email_verified"],
          userinfo: %{
            "sub" => "subject-123",
            "email" => 123,
            "email_verified" => true
          }
        )

      assert_rejected(conn)
    end

    test "rejects when userinfo's verified flag attests a different email than the id_token",
         %{conn: conn, bypass: bypass, handler: handler} do
      user = user_fixture()

      conn =
        run_callback(conn, handler, bypass,
          email: user.email,
          drop: ["email_verified"],
          userinfo: %{
            "sub" => "subject-123",
            "email" => "someone-else@example.com",
            "email_verified" => true
          }
        )

      assert_rejected(conn)
    end

    # The disabled / scheduled-deletion gate (Accounts.login_blocked?/1) runs
    # after id_token verification succeeds and the user is found, so these drive
    # the full flow via run_callback and assert the block-reason flash rather
    # than the generic sign-in failure.
    test "does not log a disabled user in via SSO", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      user = insert(:user, disabled: true)

      conn = run_callback(conn, handler, bypass, email: user.email)

      assert redirected_to(conn) == Routes.user_session_path(conn, :new)
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "disabled"
      refute get_session(conn, :user_token)
    end

    test "rejects a disabled user even when they have MFA enabled (clause order)",
         %{conn: conn, bypass: bypass, handler: handler} do
      user =
        insert(:user,
          disabled: true,
          mfa_enabled: true,
          user_totp: build(:user_totp)
        )

      conn = run_callback(conn, handler, bypass, email: user.email)

      # rejected outright, not routed into the TOTP flow
      assert redirected_to(conn) == Routes.user_session_path(conn, :new)
      refute get_session(conn, :user_token)
      refute get_session(conn, :user_totp_pending)
    end

    test "does not log a user scheduled for deletion in via SSO", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      user = insert(:user, scheduled_deletion: DateTime.utc_now())

      conn = run_callback(conn, handler, bypass, email: user.email)

      assert redirected_to(conn) == Routes.user_session_path(conn, :new)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "scheduled for deletion"

      refute get_session(conn, :user_token)
    end

    test "shows an error when the person doesn't exist", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      conn = run_callback(conn, handler, bypass, email: "invalid@user.com")

      assert redirected_to(conn) == Routes.user_session_path(conn, :new)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Could not find user account"

      refute get_session(conn, :user_token)
    end

    test "renders a 404 when a provider is missing", %{conn: conn} do
      response =
        conn
        |> get(Routes.oidc_path(conn, :new, "bar", %{"code" => "callback_code"}))

      assert response.resp_body =~ "Not Found"
      assert response.status == 404
    end

    test "redirects to login (not a token-error page) when the provider can't be built",
         %{conn: conn} do
      name = unreachable_provider_name()

      conn =
        get(
          conn,
          Routes.oidc_path(conn, :new, name, %{
            "code" => "callback_code",
            "state" => "irrelevant"
          })
        )

      assert redirected_to(conn) == Routes.user_session_path(conn, :new)
    end

    test "renders an error when a handler returns an error", %{
      conn: conn,
      handler: handler,
      bypass: bypass
    } do
      body =
        Jason.encode!(%{
          "error" => "invalid_client",
          "error_description" => "No client credentials found."
        })

      response = run_callback(conn, handler, bypass, token: {401, body})

      assert response.resp_body =~ "invalid_client"
      assert response.resp_body =~ "No client credentials found"
      assert response.status == 401
    end

    test "redirects to login (not a 500) when the token endpoint is unreachable",
         %{conn: conn, handler: handler, bypass: bypass} do
      _user = user_fixture()

      conn = get(conn, Routes.oidc_path(conn, :show, handler.name))
      {state, _nonce} = session_state_nonce(conn)

      Bypass.down(bypass)

      conn =
        get(
          conn,
          Routes.oidc_path(conn, :new, handler.name, %{
            "code" => "callback_code",
            "state" => state
          })
        )

      assert_rejected(conn)
    end

    test "keeps the newest in-flight state when concurrent flows fill the cap",
         %{
           conn: conn,
           handler: handler
         } do
      # Fill the pending map to its cap, then start one more flow: cap-then-add
      # must preserve the state we just stored (else this login could never
      # complete).
      conn =
        Enum.reduce(1..5, conn, fn _i, conn ->
          get(conn, Routes.oidc_path(conn, :show, handler.name))
        end)

      before = conn |> get_session(:oidc_pending) |> Map.keys() |> MapSet.new()
      conn = get(conn, Routes.oidc_path(conn, :show, handler.name))
      pending = get_session(conn, :oidc_pending)

      [newest] =
        pending
        |> Map.keys()
        |> MapSet.new()
        |> MapSet.difference(before)
        |> MapSet.to_list()

      assert Map.has_key?(pending, newest)
      assert map_size(pending) <= 5
    end

    test "rejects a callback with a missing state param", %{
      conn: conn,
      handler: handler
    } do
      _user = user_fixture()

      conn = get(conn, Routes.oidc_path(conn, :show, handler.name))

      conn =
        get(
          conn,
          Routes.oidc_path(conn, :new, handler.name, %{"code" => "callback_code"})
        )

      assert_rejected(conn)
    end

    test "rejects a callback whose state does not match the session", %{
      conn: conn,
      handler: handler
    } do
      _user = user_fixture()

      conn = get(conn, Routes.oidc_path(conn, :show, handler.name))

      conn =
        get(
          conn,
          Routes.oidc_path(conn, :new, handler.name, %{
            "code" => "callback_code",
            "state" => "not-the-session-state"
          })
        )

      assert_rejected(conn)
    end

    test "rejects an id_token whose nonce does not match the session", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      user = user_fixture()

      conn =
        run_callback(conn, handler, bypass,
          email: user.email,
          claims: %{"nonce" => "a-different-nonce"}
        )

      assert_rejected(conn)
    end

    test "rejects an id_token signed with the wrong key", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      user = user_fixture()

      # Forge with a different private key, but keep the header `kid` pointing at
      # the served public key so key lookup succeeds and only the signature check
      # can fail.
      conn =
        run_callback(conn, handler, bypass,
          email: user.email,
          sign_with: other_private_jwk()
        )

      assert_rejected(conn)
    end

    test "rejects an id_token whose audience is not our client", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      user = user_fixture()

      conn =
        run_callback(conn, handler, bypass,
          email: user.email,
          claims: %{"aud" => "some-other-client"}
        )

      assert_rejected(conn)
    end

    test "rejects an id_token whose issuer is wrong", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      user = user_fixture()

      conn =
        run_callback(conn, handler, bypass,
          email: user.email,
          claims: %{"iss" => "https://evil.example.com"}
        )

      assert_rejected(conn)
    end

    test "rejects an expired id_token", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      user = user_fixture()

      conn =
        run_callback(conn, handler, bypass,
          email: user.email,
          claims: %{"exp" => System.system_time(:second) - 60}
        )

      assert_rejected(conn)
    end

    test "rejects when the id_token email is not verified", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      user = user_fixture()

      # No userinfo stub: the id_token carries an email, so the flow trusts its
      # `email_verified` claim and never falls back to userinfo.
      conn =
        run_callback(conn, handler, bypass,
          email: user.email,
          claims: %{"email_verified" => false}
        )

      assert_rejected(conn)
    end

    test "rejects an unverified email from the userinfo fallback", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      user = user_fixture()

      # id_token carries no email, so the flow falls back to userinfo, which
      # marks the email explicitly unverified.
      conn =
        run_callback(conn, handler, bypass,
          email: user.email,
          drop: ["email"],
          userinfo: %{
            "sub" => "subject-123",
            "email" => user.email,
            "email_verified" => false
          }
        )

      assert_rejected(conn)
    end

    test "rejects an id_token whose email_verified claim is absent by default",
         %{
           conn: conn,
           bypass: bypass,
           handler: handler
         } do
      user = user_fixture()

      # The provider omits email_verified from both the id_token and userinfo.
      conn =
        run_callback(conn, handler, bypass,
          email: user.email,
          drop: ["email_verified"],
          userinfo: %{"sub" => "subject-123", "email" => user.email}
        )

      assert_rejected(conn)
    end

    test "accepts an absent email_verified when the provider opts in", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      # Re-register the provider with the unverified-email opt-out enabled (for a
      # trusted IdP, e.g. single-tenant Entra, that never emits email_verified).
      {:ok, trusting} =
        AuthProviders.Handler.new(handler.name,
          wellknown: handler.wellknown,
          client_id: handler.client.client_id,
          client_secret: "secret",
          redirect_uri: "http://localhost/callback_url",
          allow_unverified_email: true
        )

      AuthProviders.create_handler(trusting)

      user = user_fixture()

      conn =
        run_callback(conn, trusting, bypass,
          email: user.email,
          drop: ["email_verified"]
        )

      assert redirected_to(conn) == "/projects"
    end

    test "rejects when the userinfo subject does not match the id_token", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      user = user_fixture()

      conn =
        run_callback(conn, handler, bypass,
          email: user.email,
          drop: ["email"],
          userinfo: %{
            "sub" => "a-different-subject",
            "email" => user.email,
            "email_verified" => true
          }
        )

      assert_rejected(conn)
    end

    test "handles a provider error/consent denial without crashing", %{
      conn: conn,
      handler: handler
    } do
      conn = get(conn, Routes.oidc_path(conn, :show, handler.name))

      conn =
        get(
          conn,
          Routes.oidc_path(conn, :new, handler.name, %{
            "error" => "access_denied",
            "state" => elem(session_state_nonce(conn), 0)
          })
        )

      assert redirected_to(conn) == Routes.user_session_path(conn, :new)
      refute get_session(conn, :user_token)
    end

    test "redirects to login on a callback with neither code nor error", %{
      conn: conn,
      handler: handler
    } do
      conn = get(conn, Routes.oidc_path(conn, :new, handler.name, %{}))

      assert redirected_to(conn) == Routes.user_session_path(conn, :new)
      refute get_session(conn, :user_token)
    end

    test "reads email_verified from userinfo when the id_token omits it", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      user = user_fixture()

      conn =
        run_callback(conn, handler, bypass,
          email: user.email,
          drop: ["email_verified"],
          userinfo: %{
            "sub" => "subject-123",
            "email" => user.email,
            "email_verified" => true
          }
        )

      assert redirected_to(conn) == "/projects"
      assert get_session(conn, :user_token)
    end

    test "a second concurrent login does not break the first flow", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      user = user_fixture()

      # Start flow 1, capture its state/nonce, then start flow 2 on the same
      # session (which must not clobber flow 1's pending entry).
      conn = get(conn, Routes.oidc_path(conn, :show, handler.name))
      {state1, nonce1} = session_state_nonce(conn)
      conn = get(conn, Routes.oidc_path(conn, :show, handler.name))

      expect_token(bypass, handler.wellknown, %{
        access_token: "access_token_123",
        token_type: "Bearer",
        id_token: sign_id_token(build_claims(handler, nonce1, email: user.email))
      })

      expect_jwks(bypass, handler.wellknown.jwks_uri)

      # Complete flow 1.
      conn =
        get(
          conn,
          Routes.oidc_path(conn, :new, handler.name, %{
            "code" => "callback_code",
            "state" => state1
          })
        )

      assert redirected_to(conn) == "/projects"
    end
  end

  describe "GET /authenticate/callback" do
    setup %{conn: conn} do
      subscription_id =
        :crypto.strong_rand_bytes(4) |> Base.encode64(padding: false)

      component_id =
        :crypto.strong_rand_bytes(4) |> Base.encode64(padding: false)

      state =
        LightningWeb.OauthCredentialHelper.build_state(
          subscription_id,
          __MODULE__,
          component_id,
          "main"
        )

      LightningWeb.OauthCredentialHelper.subscribe(subscription_id)

      {:ok, conn: conn, component_id: component_id, state: state}
    end

    test "correctly broadcasts the code", %{
      conn: conn,
      component_id: component_id,
      state: state
    } do
      perform_broadcast_test(
        conn,
        state,
        component_id,
        "code",
        "callback_code",
        :code
      )
    end

    test "correctly broadcasts the error", %{
      conn: conn,
      component_id: component_id,
      state: state
    } do
      perform_broadcast_test(
        conn,
        state,
        component_id,
        "error",
        "timeout",
        :error
      )
    end

    defp perform_broadcast_test(conn, state, component_id, type, value, key) do
      response =
        conn
        |> get(
          Routes.oidc_path(conn, :new, %{
            "#{type}" => value,
            "state" => state
          })
        )

      assert_receive {:forward, LightningWeb.OidcControllerTest,
                      %{^key => ^value, id: ^component_id}}

      assert Regex.match?(
               ~r/window\.onload\s*=\s*function\(\)\s*\{\s*window\.close\(\);\s*\}/,
               response.resp_body
             )
    end
  end

  # Drives the real login flow: hits `show` to seed the session with
  # state/nonce, stubs the token (and JWKS) endpoints, then calls the callback
  # carrying the session's state so verification runs end to end.
  #
  # Options:
  #   * `:email`      - email placed in the id_token (default: unknown user)
  #   * `:claims`     - id_token claim overrides (merged over valid defaults)
  #   * `:drop`       - id_token claim keys to remove
  #   * `:sign_with`  - private JWK to sign with (default: the served key)
  #   * `:kid`        - header `kid` (default: the served key's kid)
  #   * `:state`      - state param sent back (default: the session state)
  #   * `:userinfo`   - stub the userinfo endpoint with this body
  #   * `:token`      - a raw `{status, body}` token response (bypasses id_token)
  # The controller keeps in-flight flows as a `%{state => nonce}` map; in a test
  # there's exactly one, so return its {state, nonce}.
  # Persist a provider whose discovery endpoint refuses connections, so building
  # its handler fails with a transport error (a non-atom {:error, _}) rather than
  # :not_found — the case that used to crash show/2 and mis-render new/2.
  defp unreachable_provider_name do
    dead = Bypass.open()
    Bypass.down(dead)
    name = "unreachable-#{System.unique_integer([:positive])}"

    {:ok, _config} =
      AuthProviders.create(%{
        name: name,
        client_id: "id",
        client_secret: "secret",
        discovery_url: "http://localhost:#{dead.port}/.well-known",
        redirect_uri: "http://localhost/callback"
      })

    on_exit(fn -> AuthProviders.remove_handler(name) end)
    name
  end

  defp session_state_nonce(conn) do
    case get_session(conn, :oidc_pending) do
      %{} = pending when map_size(pending) == 1 -> hd(Map.to_list(pending))
      _ -> {nil, nil}
    end
  end

  defp run_callback(conn, handler, bypass, opts) do
    conn = get(conn, Routes.oidc_path(conn, :show, handler.name))
    {session_state, session_nonce} = session_state_nonce(conn)

    case Keyword.fetch(opts, :token) do
      {:ok, token} ->
        expect_token(bypass, handler.wellknown, token)

      :error ->
        claims = build_claims(handler, session_nonce, opts)
        jwk = Keyword.get(opts, :sign_with, test_private_jwk())
        kid = Keyword.get(opts, :kid, test_kid())

        expect_token(bypass, handler.wellknown, %{
          access_token: "access_token_123",
          token_type: "Bearer",
          id_token: sign_id_token(claims, jwk, kid)
        })

        expect_jwks(bypass, handler.wellknown.jwks_uri)
    end

    if userinfo = opts[:userinfo] do
      expect_userinfo(bypass, handler.wellknown, userinfo)
    end

    state_param =
      case Keyword.fetch(opts, :state) do
        {:ok, value} -> value
        :error -> session_state
      end

    params = %{"code" => "callback_code"}

    params =
      if is_nil(state_param),
        do: params,
        else: Map.put(params, "state", state_param)

    get(conn, Routes.oidc_path(conn, :new, handler.name, params))
  end

  defp build_claims(handler, nonce, opts) do
    %{
      "iss" => handler.wellknown.issuer,
      "aud" => handler.client.client_id,
      "exp" => System.system_time(:second) + 3600,
      "nonce" => nonce,
      "sub" => "subject-123",
      "email" => Keyword.get(opts, :email, "unknown@example.com"),
      "email_verified" => true
    }
    |> Map.merge(Keyword.get(opts, :claims, %{}))
    |> drop_claims(Keyword.get(opts, :drop, []))
  end

  defp drop_claims(claims, keys),
    do: Enum.reduce(keys, claims, &Map.delete(&2, &1))

  defp assert_rejected(conn) do
    assert redirected_to(conn) == Routes.user_session_path(conn, :new)

    assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
             "We couldn't sign you in. Please try again."

    refute get_session(conn, :user_token)
  end
end
