defmodule Lightning.AuthProvidersTest do
  use Lightning.DataCase, async: true

  alias Lightning.AuthProviders
  alias Lightning.AuthProviders.{Handler, WellKnown}

  describe "Handler" do
    test "expects a name, config and a wellknown" do
      wellknown =
        WellKnown.new(%{
          "authorization_endpoint" => "http://localhost/auth_endpoint",
          "token_endpoint" => "http://localhost/token_endpoint"
        })

      {:ok, handler} =
        Handler.new(:foo,
          wellknown: wellknown,
          client_id: "bar",
          client_secret: "secret",
          redirect_uri: "http://localhost/redirect_here"
        )

      assert handler.client.client_id == "bar"
      assert handler.client.redirect_uri == "http://localhost/redirect_here"
      assert handler.wellknown == wellknown
    end
  end

  describe "AuthProviders" do
    setup do
      bypass = Bypass.open()
      handler_name = :crypto.strong_rand_bytes(6) |> Base.url_encode64()

      on_exit(fn -> AuthProviders.remove_handler(handler_name) end)

      {:ok,
       bypass: bypass,
       endpoint_url: "http://localhost:#{bypass.port}",
       handler_name: handler_name}
    end

    test "end to end", %{
      bypass: bypass,
      endpoint_url: endpoint_url,
      handler_name: handler_name
    } do
      Bypass.expect_once(bypass, "GET", "auth/.well-known", fn conn ->
        Plug.Conn.resp(
          conn,
          200,
          %{
            "authorization_endpoint" => "#{endpoint_url}/auth_endpoint",
            "token_endpoint" => "#{endpoint_url}/token_endpoint"
          }
          |> Jason.encode!()
        )
      end)

      {:ok, handler} =
        AuthProviders.build_handler(
          handler_name,
          discovery_url: endpoint_url <> "/auth/.well-known",
          client_id: "the client id",
          client_secret: "secret",
          redirect_uri: endpoint_url <> "/redirect_here"
        )

      AuthProviders.create_handler(handler)

      assert AuthProviders.get_handler(handler_name) == {:ok, handler},
             "Should find the handler that was just created"

      assert AuthProviders.get_handler("bar") == {:error, :not_found},
             "Shouldn't be able to find a non-existant handler"

      auth_url =
        URI.new!(endpoint_url)
        |> URI.merge(%URI{
          path: "/auth_endpoint",
          query:
            URI.encode_query(%{
              "client_id" => "the client id",
              "redirect_uri" => endpoint_url <> "/redirect_here",
              "response_type" => "code"
            })
        })
        |> URI.to_string()

      assert Handler.authorize_url(handler) == auth_url
    end
  end
end
