defmodule LightningWeb.AuthProvidersLiveTest do
  use LightningWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Lightning.BypassHelpers

  alias Lightning.AuthProviders

  # The page is drawn by React from data-props. The form's own checks, the
  # Test button's states, the redirect URI preview and the field errors are
  # tested in the design system's AdminAuthProvidersPage.test.tsx; the events
  # the island sends in assets/test/design-system/. These tests cover the
  # gate and what the server answers.
  @page "#admin-auth-providers-page"

  defp props(view), do: page_props(view, @page)["provider"]

  defp values(endpoint_url, handler_name, overrides \\ %{}) do
    Map.merge(
      %{
        "name" => handler_name,
        "discoveryUrl" => "#{endpoint_url}/auth/.well-known",
        "clientId" => "client-id",
        "clientSecret" => "client-secret",
        "redirectHost" => "http://localhost:4002",
        "allowUnverifiedEmail" => false
      },
      overrides
    )
  end

  defp save(view, values),
    do: push_page_event(view, @page, "save_provider", values)

  defp test_provider(view, values),
    do: push_page_event(view, @page, "test_provider", values)

  describe "index for superuser" do
    setup :register_and_log_in_superuser

    test "super users can access the auth providers page", %{
      conn: conn
    } do
      {:ok, view, html} =
        live(conn, ~p"/settings/authentication", on_error: :raise)
        |> follow_redirect(conn, ~p"/settings/authentication/new")

      assert html =~ "Users"
      assert html =~ "Back"

      assert %{
               "id" => nil,
               "name" => "",
               "discoveryUrl" => "",
               "clientId" => "",
               "hasClientSecret" => false,
               "redirectHost" => redirect_host,
               "allowUnverifiedEmail" => false
             } = props(view)

      assert redirect_host =~ "http://"
    end
  end

  describe "index for user" do
    setup :register_and_log_in_user

    test "a regular user cannot access the auth providers page", %{
      conn: conn
    } do
      {:ok, conn} =
        live(conn, ~p"/settings/authentication", on_error: :raise)
        |> follow_redirect(conn, "/projects")

      assert conn.resp_body =~ "Sorry, you don&#39;t have access to that."
    end
  end

  describe "refusing a provider" do
    setup :register_and_log_in_superuser

    # Nothing here reaches the network: every save is refused before that.
    test "refuses a provider with a blank or malformed name before saving", %{
      conn: conn
    } do
      endpoint_url = "http://localhost:1"
      handler_name = "refused"
      {:ok, view, _html} = live(conn, ~p"/settings/authentication/new")

      save(view, values(endpoint_url, handler_name, %{"name" => ""}))
      assert_reply(view, %{fieldErrors: %{"name" => [blank]}})
      assert blank =~ "can't be blank"

      save(view, values(endpoint_url, handler_name, %{"name" => "Not Lower"}))
      assert_reply(view, %{fieldErrors: %{"name" => [format]}})
      assert format =~ "lower-case"

      # A host the URI parser rejects is a field error, not a crash.
      save(
        view,
        values(endpoint_url, handler_name, %{"redirectHost" => "http://bad host"})
      )

      assert_reply(view, %{
        fieldErrors: %{"redirectHost" => ["must be a valid URL"]}
      })

      # The columns hold 255 characters; a longer value is a field error, not a crash.
      save(
        view,
        values(endpoint_url, handler_name, %{
          "clientId" => String.duplicate("a", 256)
        })
      )

      assert_reply(view, %{fieldErrors: %{"clientId" => [long]}})
      assert long =~ "at most 255"

      # No stored secret on /new, so a blank one is a missing one.
      save(view, values(endpoint_url, handler_name, %{"clientSecret" => ""}))
      assert_reply(view, %{fieldErrors: %{"clientSecret" => [_]}})

      # Crafted payloads: non-strings read as blank, a non-map is refused.
      save(view, %{"name" => 1, "discoveryUrl" => nil})
      assert_reply(view, %{fieldErrors: %{"name" => [_], "clientId" => [_]}})

      push_page_event(view, @page, "save_provider", ["x"])
      assert_reply(view, %{error: "Invalid request"})

      refute AuthProviders.get_existing()
    end
  end

  describe "adding an auth provider" do
    setup :register_and_log_in_superuser

    setup do
      bypass = Bypass.open()

      handler_name =
        :crypto.strong_rand_bytes(6) |> Base.url_encode64() |> String.downcase()

      Bypass.expect_once(bypass, "GET", "auth/.well-know", fn conn ->
        Plug.Conn.resp(
          conn,
          404,
          ""
        )
      end)

      expect_wellknown(bypass)

      on_exit(fn -> AuthProviders.remove_handler(handler_name) end)

      {:ok,
       bypass: bypass,
       endpoint_url: "http://localhost:#{bypass.port}",
       handler_name: handler_name}
    end

    test "can create a new auth provider", %{
      conn: conn,
      endpoint_url: endpoint_url,
      handler_name: handler_name
    } do
      {:ok, view, _html} =
        live(conn, Routes.auth_providers_index_path(conn, :edit),
          on_error: :raise
        )
        |> follow_redirect(conn, Routes.auth_providers_index_path(conn, :new))

      test_provider(
        view,
        values(endpoint_url, handler_name, %{
          "discoveryUrl" => "#{endpoint_url}/auth/.well-know"
        })
      )

      assert_reply(view, %{error: "error parsing .well-known"})

      test_provider(view, values(endpoint_url, handler_name))
      assert_reply(view, %{})

      # Nothing is written by a test; nothing is removed without a provider.
      refute AuthProviders.get_existing()
      push_page_event(view, @page, "remove_provider")
      assert_reply(view, %{error: "No provider is configured"})

      {:ok, view, html} =
        view
        |> save(
          values(endpoint_url, handler_name, %{"allowUnverifiedEmail" => true})
        )
        |> follow_redirect(conn, Routes.auth_providers_index_path(conn, :edit))

      assert html =~ "Authentication Provider created."

      assert %{allow_unverified_email: true} =
               AuthProviders.get_existing(handler_name),
             "Should be able to find the handler in the store"

      assert AuthProviders.get_handler(handler_name)

      # The stored secret is not sent to the page, only that there is one.
      assert %{
               "id" => id,
               "hasClientSecret" => true,
               "allowUnverifiedEmail" => true
             } =
               props(view)

      assert is_binary(id)
      refute Map.has_key?(props(view), "clientSecret")
      refute render(view) =~ "client-secret"

      # One provider: a second one from /new is refused.
      {:ok, new_view, _html} = live(conn, ~p"/settings/authentication/new")
      save(new_view, values(endpoint_url, "second"))

      assert_reply(new_view, %{
        error: "A provider is already configured. Edit it instead."
      })

      refute AuthProviders.get_existing("second")

      assert {:error, {:live_redirect, %{to: to}}} =
               push_page_event(view, @page, "remove_provider")

      assert to == Routes.auth_providers_index_path(conn, :new)

      refute AuthProviders.get_existing(handler_name)
      assert {:error, :not_found} == AuthProviders.get_handler(handler_name)
    end
  end

  describe "editing an auth provider" do
    setup :register_and_log_in_superuser

    setup do
      bypass = Bypass.open()

      handler_name =
        :crypto.strong_rand_bytes(6) |> Base.url_encode64() |> String.downcase()

      expect_wellknown(bypass)

      on_exit(fn -> AuthProviders.remove_handler(handler_name) end)

      {:ok,
       bypass: bypass,
       endpoint_url: "http://localhost:#{bypass.port}",
       handler_name: handler_name}
    end

    test "can update an existing auth provider", %{
      conn: conn,
      endpoint_url: endpoint_url,
      handler_name: handler_name
    } do
      AuthProviders.create(%{
        name: handler_name,
        discovery_url: "#{endpoint_url}/auth/.well-known",
        client_id: "id",
        client_secret: "secret",
        redirect_uri: "http://localhost/callback_url"
      })

      {:ok, _handler} = AuthProviders.get_handler(handler_name)

      {:ok, view, _html} =
        live(conn, Routes.auth_providers_index_path(conn, :edit),
          on_error: :raise
        )

      assert %{
               "name" => ^handler_name,
               "clientId" => "id",
               "hasClientSecret" => true,
               "redirectHost" => "http://localhost/"
             } = props(view)

      refute render(view) =~ "secret"

      # A blank secret keeps the stored one, for Test and for Save.
      current =
        values(endpoint_url, handler_name, %{
          "clientId" => "new-client-id",
          "clientSecret" => "",
          "redirectHost" => "http://localhost:3030"
        })

      test_provider(view, current)
      assert_reply(view, %{})

      save(view, current)
      assert_reply(view, %{})
      assert render(view) =~ "Authentication Provider updated."

      new_redirect_uri =
        "http://localhost:3030/authenticate/#{handler_name}/callback"

      {:ok, handler} = AuthProviders.get_handler(handler_name)

      assert handler.client.client_id == "new-client-id"
      assert handler.client.client_secret == "secret"
      assert handler.client.redirect_uri == new_redirect_uri

      assert %{"hasClientSecret" => true, "clientId" => "new-client-id"} =
               props(view)

      assert {:error, {:live_redirect, %{to: to}}} =
               push_page_event(view, @page, "remove_provider")

      assert to == Routes.auth_providers_index_path(conn, :new)

      refute AuthProviders.get_existing(handler_name)
      assert {:error, :not_found} == AuthProviders.get_handler(handler_name)
    end
  end
end
