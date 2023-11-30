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

      assert redirected_to(conn) == "/"
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
      expect_userinfo(bypass, handler.wellknown, %{"email" => user.email})

      conn =
        conn
        |> get(
          Routes.oidc_path(conn, :new, handler.name, %{"code" => "callback_code"})
        )

      assert redirected_to(conn) == "/"
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

    test "shows an error when the person doesn't exist", %{
      conn: conn,
      bypass: bypass,
      handler: handler
    } do
      expect_token(bypass, handler.wellknown)

      expect_userinfo(bypass, handler.wellknown, %{"email" => "invalid@user.com"})

      conn =
        conn
        |> get(
          Routes.oidc_path(conn, :new, handler.name, %{"code" => "callback_code"})
        )

      assert redirected_to(conn) == Routes.user_session_path(conn, :new)
    end

    test "renders a 404 when a provider is missing", %{conn: conn} do
      response =
        conn
        |> get(Routes.oidc_path(conn, :new, "bar", %{"code" => "callback_code"}))

      assert response.resp_body =~ "Not Found"
      assert response.status == 404
    end

    test "renders an error when a handler returns an error", %{
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

      response =
        conn
        |> get(
          Routes.oidc_path(conn, :new, handler.name, %{"code" => "callback_code"})
        )

      assert response.resp_body =~ "invalid_client"
      assert response.resp_body =~ "No client credentials found"
      assert response.status == 401
    end
  end

  describe "GET /authenticate/callback" do
    test "correctly broadcasts the code", %{conn: conn} do
      subscription_id =
        :crypto.strong_rand_bytes(4) |> Base.encode64(padding: false)

      component_id =
        :crypto.strong_rand_bytes(4) |> Base.encode64(padding: false)

      state =
        LightningWeb.OauthCredentialHelper.build_state(
          subscription_id,
          __MODULE__,
          component_id
        )

      LightningWeb.OauthCredentialHelper.subscribe(subscription_id)

      response =
        conn
        |> get(
          Routes.oidc_path(conn, :new, %{
            "code" => "callback_code",
            "state" => state
          })
        )

      assert_receive {:forward, LightningWeb.OidcControllerTest,
                      [id: ^component_id, code: "callback_code"]}

      assert Regex.match?(
               ~r/window\.onload\s*=\s*function\(\)\s*\{\s*window\.close\(\);\s*\}/,
               response.resp_body
             )
    end
  end
end
