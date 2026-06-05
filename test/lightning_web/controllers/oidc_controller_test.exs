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

  # A handler that resolves email from a dedicated emails endpoint, mirroring
  # GitHub's `/user/emails`.
  def setup_handler_with_user_emails(_) do
    bypass = Bypass.open()

    wellknown = %AuthProviders.WellKnown{
      authorization_endpoint: "#{endpoint_url(bypass)}/authorization_endpoint",
      token_endpoint: "#{endpoint_url(bypass)}/token_endpoint",
      userinfo_endpoint: "#{endpoint_url(bypass)}/userinfo_endpoint",
      user_emails_endpoint: "#{endpoint_url(bypass)}/user_emails_endpoint"
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

    test "logs in users whose identity is already linked", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      expect_token(bypass, handler.wellknown)

      user = Lightning.AccountsFixtures.user_fixture()

      insert(:user_identity,
        user: user,
        provider: handler.name,
        uid: "sub-#{user.id}"
      )

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

    test "redirects to login with a notice when email matches an existing account",
         %{conn: conn, bypass: bypass, handler: handler} do
      expect_token(bypass, handler.wellknown)
      user = Lightning.AccountsFixtures.user_fixture()

      expect_userinfo(bypass, handler.wellknown, %{
        "email" => user.email,
        "sub" => "unlinked-uid"
      })

      conn =
        conn
        |> get(
          Routes.oidc_path(conn, :new, handler.name, %{"code" => "callback_code"})
        )

      assert redirected_to(conn) == Routes.user_session_path(conn, :new)

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "An account already exists"

      assert Phoenix.Flash.get(conn.assigns.flash, :info) =~
               "link your #{String.capitalize(handler.name)} account"

      # No identity was silently created
      refute Lightning.Accounts.get_user_by_identity(
               handler.name,
               "unlinked-uid"
             )
    end

    test "prompts the user to confirm before creating a brand-new account",
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

      assert redirected_to(conn) == ~p"/authenticate/signup/confirm"

      assert get_session(conn, :sso_pending_signup) == %{
               "provider" => handler.name,
               "uid" => "fresh-uid-1",
               "email" => email,
               "first_name" => "First",
               "last_name" => "Last"
             }

      # No account or identity is created until the user confirms
      refute Lightning.Accounts.get_user_by_email(email)
      refute Lightning.Accounts.get_user_by_identity(handler.name, "fresh-uid-1")
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

      insert(:user_identity,
        user: user,
        provider: handler.name,
        uid: "mfa-uid-#{user.id}"
      )

      expect_userinfo(bypass, handler.wellknown, %{
        "email" => user.email,
        "sub" => "mfa-uid-#{user.id}"
      })

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

  # GitHub's /user endpoint returns a null email for users without a public
  # profile email, even when the user:email scope is granted. Providers that set
  # a `user_emails_endpoint` must resolve the primary, verified email from it.
  describe "GET /authenticate/:provider/callback (email resolution fallback)" do
    setup :setup_handler_with_user_emails

    test "resolves the primary verified email when userinfo has none", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      expect_token(bypass, handler.wellknown)

      # userinfo carries no email (the GitHub "no public email" case)
      expect_userinfo(bypass, handler.wellknown, %{"sub" => "gh-uid-1"})

      expect_user_emails(bypass, handler.wellknown, [
        %{
          "email" => "secondary@example.com",
          "primary" => false,
          "verified" => true
        },
        %{
          "email" => "primary@example.com",
          "primary" => true,
          "verified" => true
        },
        %{
          "email" => "unverified@example.com",
          "primary" => false,
          "verified" => false
        }
      ])

      conn =
        get(
          conn,
          Routes.oidc_path(conn, :new, handler.name, %{"code" => "callback_code"})
        )

      # The signup confirmation flow is reached, meaning an email was resolved.
      assert redirected_to(conn) == ~p"/authenticate/signup/confirm"

      assert get_session(conn, :sso_pending_signup)["email"] ==
               "primary@example.com"
    end

    test "falls back to any verified email when none is marked primary", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      expect_token(bypass, handler.wellknown)
      expect_userinfo(bypass, handler.wellknown, %{"sub" => "gh-uid-2"})

      expect_user_emails(bypass, handler.wellknown, [
        %{
          "email" => "unverified@example.com",
          "primary" => true,
          "verified" => false
        },
        %{
          "email" => "verified@example.com",
          "primary" => false,
          "verified" => true
        }
      ])

      conn =
        get(
          conn,
          Routes.oidc_path(conn, :new, handler.name, %{"code" => "callback_code"})
        )

      assert get_session(conn, :sso_pending_signup)["email"] ==
               "verified@example.com"
    end

    test "errors when the emails endpoint has no verified address", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      expect_token(bypass, handler.wellknown)
      expect_userinfo(bypass, handler.wellknown, %{"sub" => "gh-uid-3"})

      expect_user_emails(bypass, handler.wellknown, [
        %{
          "email" => "unverified@example.com",
          "primary" => true,
          "verified" => false
        }
      ])

      conn =
        get(
          conn,
          Routes.oidc_path(conn, :new, handler.name, %{"code" => "callback_code"})
        )

      assert redirected_to(conn) == Routes.user_session_path(conn, :new)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "Could not retrieve your email"
    end

    test "prefers the userinfo email and skips the emails endpoint when present",
         %{conn: conn, bypass: bypass, handler: handler} do
      expect_token(bypass, handler.wellknown)

      expect_userinfo(bypass, handler.wellknown, %{
        "sub" => "gh-uid-4",
        "email" => "public@example.com"
      })

      # No expect_user_emails/3 stub: if the endpoint were called, Bypass would
      # fail the test, proving the extra request is skipped.

      conn =
        get(
          conn,
          Routes.oidc_path(conn, :new, handler.name, %{"code" => "callback_code"})
        )

      assert get_session(conn, :sso_pending_signup)["email"] ==
               "public@example.com"
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

  describe "SSO signup confirmation flow" do
    test "GET /authenticate/signup/confirm renders the confirmation page",
         %{conn: conn} do
      pending = %{
        "provider" => "github",
        "uid" => "uid-123",
        "email" => "new@example.com",
        "first_name" => "Pat",
        "last_name" => "Doe"
      }

      conn =
        conn
        |> Plug.Test.init_test_session(%{sso_pending_signup: pending})
        |> get(~p"/authenticate/signup/confirm")

      html = html_response(conn, 200)
      assert html =~ "Create your account"
      assert html =~ "new@example.com"
      assert html =~ "Github"
      assert html =~ "Pat Doe"
    end

    test "GET /authenticate/signup/confirm redirects to login when no pending signup",
         %{conn: conn} do
      conn = get(conn, ~p"/authenticate/signup/confirm")
      assert redirected_to(conn) == Routes.user_session_path(conn, :new)
    end

    test "POST /authenticate/signup/confirm creates the account and logs in",
         %{conn: conn} do
      email = "confirm-signup-#{System.unique_integer([:positive])}@example.com"

      pending = %{
        "provider" => "github",
        "uid" => "confirm-uid",
        "email" => email,
        "first_name" => "Alice",
        "last_name" => "Smith"
      }

      conn =
        conn
        |> Plug.Test.init_test_session(%{sso_pending_signup: pending})
        |> post(~p"/authenticate/signup/confirm", %{})

      assert redirected_to(conn) == "/projects"

      user = Lightning.Accounts.get_user_by_email(email)
      assert user
      assert user.first_name == "Alice"
      assert user.last_name == "Smith"
      assert is_nil(user.hashed_password)
      refute is_nil(user.confirmed_at)

      assert %Lightning.Accounts.User{id: same_id} =
               Lightning.Accounts.get_user_by_identity("github", "confirm-uid")

      assert same_id == user.id
      refute get_session(conn, :sso_pending_signup)
    end

    test "POST /authenticate/signup/confirm redirects when there is no pending signup",
         %{conn: conn} do
      conn = post(conn, ~p"/authenticate/signup/confirm", %{})
      assert redirected_to(conn) == Routes.user_session_path(conn, :new)

      assert Phoenix.Flash.get(conn.assigns.flash, :error) =~
               "No pending sign-up"
    end

    test "GET /authenticate/signup/cancel clears the pending signup",
         %{conn: conn} do
      pending = %{
        "provider" => "github",
        "uid" => "cancel-uid",
        "email" => "cancel@example.com",
        "first_name" => "C",
        "last_name" => "X"
      }

      conn =
        conn
        |> Plug.Test.init_test_session(%{sso_pending_signup: pending})
        |> get(~p"/authenticate/signup/cancel")

      assert redirected_to(conn) == Routes.user_session_path(conn, :new)
      refute get_session(conn, :sso_pending_signup)
      refute Lightning.Accounts.get_user_by_email("cancel@example.com")
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
