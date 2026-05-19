defmodule LightningWeb.OidcControllerTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.BypassHelpers
  import Lightning.AccountsFixtures
  import Lightning.Factories

  alias Lightning.AuthProviders

  def setup_handler(_) do
    bypass = Bypass.open()

    wellknown = %AuthProviders.WellKnown{
      authorization_endpoint: "#{endpoint_url(bypass)}/authorization_endpoint",
      token_endpoint: "#{endpoint_url(bypass)}/token_endpoint",
      userinfo_endpoint: "#{endpoint_url(bypass)}/userinfo_endpoint"
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

    test "redirects to provider authorize_url", %{conn: conn, handler: handler} do
      conn = conn |> get(Routes.oidc_path(conn, :show, handler.name))

      assert redirected_to(conn) ==
               AuthProviders.Handler.authorize_url(handler)
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
  end

  describe "GET /authenticate/:provider/callback" do
    setup :setup_handler

    test "logs the given person in", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      expect_token(bypass, handler.wellknown)

      user = Lightning.AccountsFixtures.user_fixture()

      expect_userinfo(bypass, handler.wellknown, %{
        "email" => user.email,
        "sub" => "sub-#{user.id}"
      })

      conn =
        conn
        |> get(
          Routes.oidc_path(conn, :new, handler.name, %{"code" => "callback_code"})
        )

      assert redirected_to(conn) == "/projects"
    end

    test "auto-links an identity for an existing email-only user and logs them in",
         %{conn: conn, bypass: bypass, handler: handler} do
      expect_token(bypass, handler.wellknown)
      user = Lightning.AccountsFixtures.user_fixture()

      expect_userinfo(bypass, handler.wellknown, %{
        "email" => user.email,
        "sub" => "github-uid-1"
      })

      conn =
        conn
        |> get(
          Routes.oidc_path(conn, :new, handler.name, %{"code" => "callback_code"})
        )

      assert redirected_to(conn) == "/projects"

      assert %Lightning.Accounts.User{id: same_id} =
               Lightning.Accounts.get_user_by_identity(
                 handler.name,
                 "github-uid-1"
               )

      assert same_id == user.id
    end

    test "auto-registers a new user when there is no existing email or identity",
         %{conn: conn, bypass: bypass, handler: handler} do
      expect_token(bypass, handler.wellknown)
      email = "new-sso-user-#{System.unique_integer([:positive])}@example.com"

      expect_userinfo(bypass, handler.wellknown, %{
        "email" => email,
        "sub" => "fresh-uid-1",
        "name" => "First Last"
      })

      conn =
        conn
        |> get(
          Routes.oidc_path(conn, :new, handler.name, %{"code" => "callback_code"})
        )

      assert redirected_to(conn) == "/projects"

      user = Lightning.Accounts.get_user_by_email(email)
      assert user
      assert user.first_name == "First"
      assert user.last_name == "Last"
      assert is_nil(user.hashed_password)
      refute is_nil(user.confirmed_at)

      assert Lightning.Accounts.get_user_by_identity(handler.name, "fresh-uid-1")
    end

    test "redirects to login when userinfo has no email", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      expect_token(bypass, handler.wellknown)

      expect_userinfo(bypass, handler.wellknown, %{"sub" => "abc"})

      conn =
        conn
        |> get(
          Routes.oidc_path(conn, :new, handler.name, %{"code" => "callback_code"})
        )

      assert redirected_to(conn) == Routes.user_session_path(conn, :new)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Could not retrieve your email"
    end

    test "logs the person in but marks totp as pending for users wth MFA enabled",
         %{
           conn: conn,
           bypass: bypass,
           handler: handler
         } do
      expect_token(bypass, handler.wellknown)

      user = insert(:user, mfa_enabled: true, user_totp: build(:user_totp))

      expect_userinfo(bypass, handler.wellknown, %{"email" => user.email})

      conn =
        conn
        |> get(
          Routes.oidc_path(conn, :new, handler.name, %{"code" => "callback_code"})
        )

      assert get_session(conn, :user_totp_pending)

      assert redirected_to(conn) ==
               Routes.user_totp_path(conn, :new, user: %{"remember_me" => true})

      # The user is redirected to the TOTP page if they try accessing other pages
      conn = get(conn, "/")
      assert redirected_to(conn) == Routes.user_totp_path(conn, :new)
    end

    test "redirects to login when userinfo has no uid", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      expect_token(bypass, handler.wellknown)

      expect_userinfo(bypass, handler.wellknown, %{"email" => "x@example.com"})

      conn =
        conn
        |> get(
          Routes.oidc_path(conn, :new, handler.name, %{"code" => "callback_code"})
        )

      assert redirected_to(conn) == Routes.user_session_path(conn, :new)
    end

    test "redirects to login when a provider is missing", %{conn: conn} do
      conn =
        conn
        |> get(Routes.oidc_path(conn, :new, "bar", %{"code" => "callback_code"}))

      assert redirected_to(conn) == Routes.user_session_path(conn, :new)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Authentication failed"
    end

    test "redirects to login when a handler returns an error", %{
      conn: conn,
      handler: handler,
      bypass: bypass
    } do
      expect_token(
        bypass,
        handler.wellknown,
        {401,
         %{
           "error" => "invalid_client",
           "error_description" => "No client credentials found."
         }
         |> Jason.encode!()}
      )

      conn =
        conn
        |> get(
          Routes.oidc_path(conn, :new, handler.name, %{"code" => "callback_code"})
        )

      assert redirected_to(conn) == Routes.user_session_path(conn, :new)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) ==
               "Authentication failed"
    end
  end

  describe "GET /authenticate/:provider/link" do
    setup :setup_handler

    test "redirects to the provider authorize url for a logged-in user", %{
      conn: conn,
      handler: handler
    } do
      user = user_fixture()

      conn =
        conn
        |> log_in_user(user)
        |> get(Routes.oidc_path(conn, :link, handler.name))

      assert redirected_to(conn) ==
               AuthProviders.Handler.authorize_url(handler)

      assert get_session(conn, :sso_link_intent_provider) == handler.name
    end

    test "redirects unauthenticated users to log in", %{
      conn: conn,
      handler: handler
    } do
      conn = get(conn, Routes.oidc_path(conn, :link, handler.name))
      assert redirected_to(conn) == Routes.user_session_path(conn, :new)
    end
  end

  describe "GET /authenticate/:provider/callback (link flow)" do
    setup :setup_handler

    test "links the identity to the current user", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      user = user_fixture()
      expect_token(bypass, handler.wellknown)

      expect_userinfo(bypass, handler.wellknown, %{
        "email" => "anything@example.com",
        "sub" => "new-link-uid"
      })

      conn =
        conn
        |> log_in_user(user)
        |> put_session(:sso_link_intent_provider, handler.name)
        |> get(
          Routes.oidc_path(conn, :new, handler.name, %{"code" => "callback_code"})
        )

      assert redirected_to(conn) == ~p"/profile"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "Linked your"

      assert %Lightning.Accounts.User{id: same_id} =
               Lightning.Accounts.get_user_by_identity(
                 handler.name,
                 "new-link-uid"
               )

      assert same_id == user.id
    end

    test "flashes info when identity is already linked to the same account", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      user = user_fixture()

      insert(:user_identity,
        user: user,
        provider: handler.name,
        uid: "existing-uid"
      )

      expect_token(bypass, handler.wellknown)

      expect_userinfo(bypass, handler.wellknown, %{
        "email" => user.email,
        "sub" => "existing-uid"
      })

      conn =
        conn
        |> log_in_user(user)
        |> put_session(:sso_link_intent_provider, handler.name)
        |> get(
          Routes.oidc_path(conn, :new, handler.name, %{"code" => "callback_code"})
        )

      assert redirected_to(conn) == ~p"/profile"
      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~ "already linked"
    end

    test "rejects linking an identity already claimed by another user", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      user = user_fixture()
      other_user = user_fixture()

      insert(:user_identity,
        user: other_user,
        provider: handler.name,
        uid: "claimed-uid"
      )

      expect_token(bypass, handler.wellknown)

      expect_userinfo(bypass, handler.wellknown, %{
        "email" => "anything@example.com",
        "sub" => "claimed-uid"
      })

      conn =
        conn
        |> log_in_user(user)
        |> put_session(:sso_link_intent_provider, handler.name)
        |> get(
          Routes.oidc_path(conn, :new, handler.name, %{"code" => "callback_code"})
        )

      assert redirected_to(conn) == ~p"/profile"
      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~ "already linked"

      # Still belongs to the other user
      assert %Lightning.Accounts.User{id: same_id} =
               Lightning.Accounts.get_user_by_identity(
                 handler.name,
                 "claimed-uid"
               )

      assert same_id == other_user.id
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
end
