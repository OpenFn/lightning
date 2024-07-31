defmodule LightningWeb.AuthProvidersLiveTest do
  use LightningWeb.ConnCase, async: false

  import Phoenix.LiveViewTest
  import Lightning.BypassHelpers

  alias Lightning.AuthProviders

  describe "index for superuser" do
    setup :register_and_log_in_superuser

    test "super users can access the auth providers page", %{
      conn: conn
    } do
      {:ok, _index_live, html} =
        live(conn, ~p"/settings/authentication")
        |> follow_redirect(conn, ~p"/settings/authentication/new")

      assert html =~ "Users"
      assert html =~ "Back"
    end
  end

  describe "index for user" do
    setup :register_and_log_in_user

    test "a regular user cannot access the auth providers page", %{
      conn: conn
    } do
      {:ok, _index_live, html} =
        live(conn, ~p"/settings/authentication")
        |> follow_redirect(conn, "/projects")

      assert html =~ "Sorry, you don&#39;t have access to that."
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
        live(conn, Routes.auth_providers_index_path(conn, :edit))
        |> follow_redirect(conn, Routes.auth_providers_index_path(conn, :new))

      assert view
             |> form("#auth-provider-form", auth_provider: %{name: ""})
             |> render_change()

      assert view |> get_error_tag("name") =~
               "can&#39;t be blank"

      assert view
             |> form("#auth-provider-form",
               auth_provider: %{
                 name: handler_name,
                 discovery_url: "#{endpoint_url}/auth/.well-know",
                 client_id: "client-id",
                 client_secret: "client-secret"
               }
             )
             |> render_change()

      assert view |> element("button#test-button", "Test") |> render_click() =~
               "error parsing .well-known"

      assert view
             |> form("#auth-provider-form",
               auth_provider: %{
                 discovery_url: "#{endpoint_url}/auth/.well-known"
               }
             )
             |> render_change()

      assert view |> element("button", "Test") |> render_click() =~
               "Success"

      {:ok, view, html} =
        view
        |> form("#auth-provider-form")
        |> render_submit()
        |> follow_redirect(conn, Routes.auth_providers_index_path(conn, :edit))

      assert html =~ "Authentication Provider created."

      assert AuthProviders.get_existing(handler_name),
             "Should be able to find the handler in the store"

      assert AuthProviders.get_handler(handler_name)

      assert view |> element("button", "Remove") |> render_click()

      refute AuthProviders.get_existing(handler_name)
      assert {:error, :not_found} == AuthProviders.get_handler(handler_name)

      #  "Should be able to find the handler in the store"
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
        live(conn, Routes.auth_providers_index_path(conn, :edit))

      assert view |> element("button#test-button", "Test") |> render_click() =~
               "Success"

      assert view
             |> form("#auth-provider-form",
               auth_provider: %{
                 client_id: "new-client-id",
                 redirect_host: "http://localhost:3030"
               }
             )
             |> render_change()

      assert view
             |> element("#auth-provider-form")
             |> render_submit() =~ "Authentication Provider updated."

      new_redirect_uri =
        "http://localhost:3030/authenticate/#{handler_name}/callback"

      assert view
             |> element(
               "#redirect-uri-preview",
               new_redirect_uri
             )
             |> render()

      {:ok, handler} = AuthProviders.get_handler(handler_name)

      assert handler.client.client_id == "new-client-id"
      assert handler.client.redirect_uri == new_redirect_uri

      assert view
             |> element("button", "Remove")
             |> render_click()
             |> follow_redirect(
               conn,
               Routes.auth_providers_index_path(conn, :new)
             )

      refute AuthProviders.get_existing(handler_name)
      assert {:error, :not_found} == AuthProviders.get_handler(handler_name)
    end
  end

  defp get_error_tag(live, field) do
    live
    |> element(~s{#auth-provider-form_#{field} + [data-tag="error_message"]})
    |> render()
  end
end
