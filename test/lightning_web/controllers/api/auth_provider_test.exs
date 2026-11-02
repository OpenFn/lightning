defmodule LightningWeb.API.AuthProviderTest do
  # Sign-in handlers are cached for the whole instance, which GET
  # /api/instance lists, so these tests run alone.
  use LightningWeb.ConnCase, async: false

  import Lightning.BypassHelpers
  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.SessionHelpers

  alias Lightning.Accounts
  alias Lightning.AuthProviders
  alias Lightning.AuthProviders.AuthConfig
  alias Lightning.Repo

  setup do
    bypass = Bypass.open()
    name = "sso-" <> String.downcase(Base.encode16(:crypto.strong_rand_bytes(4)))
    on_exit(fn -> AuthProviders.remove_handler(name) end)

    %{
      bypass: bypass,
      name: name,
      discovery_url: "http://localhost:#{bypass.port}/auth/.well-known"
    }
  end

  defp superuser_conn do
    user = insert(:user, role: :superuser)

    build_conn()
    |> put_req_header("accept", "application/json")
    |> put_req_header("content-type", "application/json")
    |> put_req_header(
      "authorization",
      "Bearer " <> Accounts.generate_api_token(user)
    )
  end

  defp insert_provider(%{name: name, discovery_url: discovery_url}) do
    Repo.insert!(%AuthConfig{
      name: name,
      discovery_url: discovery_url,
      client_id: "lightning",
      client_secret: "kept-secret",
      redirect_uri: "https://old.example.org/authenticate/#{name}/callback"
    })
  end

  defp provider_body(provider) do
    %{
      "name" => provider.name,
      "discovery_url" => provider.discovery_url,
      "client_id" => provider.client_id,
      "redirect_uri" => provider.redirect_uri,
      "inserted_at" => DateTime.to_iso8601(provider.inserted_at),
      "updated_at" => DateTime.to_iso8601(provider.updated_at)
    }
  end

  defp redirect_uri(name),
    do: LightningWeb.Endpoint.url() <> "/authenticate/#{name}/callback"

  describe "reading" do
    test "answers the provider without its client secret", ctx do
      provider = insert_provider(ctx)

      conn = get(superuser_conn(), ~p"/api/auth_provider")

      assert json_response(conn, 200) == %{"data" => provider_body(provider)}
    end

    test "answers a superuser's session token too", ctx do
      provider = insert_provider(ctx)

      conn =
        build_conn()
        |> session_conn(insert(:user, role: :superuser))
        |> get(~p"/api/auth_provider")

      assert json_response(conn, 200) == %{"data" => provider_body(provider)}
    end

    test "answers not_found when none is set up" do
      superuser_conn()
      |> get(~p"/api/auth_provider")
      |> assert_problem(404, :not_found, [])
    end
  end

  describe "who may reach it" do
    test "anyone but a superuser is forbidden, whether or not a provider is set up",
         ctx do
      user = insert(:user)

      for setup <- [:none, :set_up] do
        if setup == :set_up, do: insert_provider(ctx)

        for conn <- [
              build_conn()
              |> put_req_header("accept", "application/json")
              |> put_req_header(
                "authorization",
                "Bearer " <> Accounts.generate_api_token(user)
              ),
              session_conn(build_conn(), user)
            ] do
          for answer <- [
                get(conn, ~p"/api/auth_provider"),
                put(conn, ~p"/api/auth_provider", %{"name" => "x"}),
                delete(conn, ~p"/api/auth_provider")
              ] do
            assert_problem(answer, 403, :forbidden, [])
          end
        end
      end

      assert [%AuthConfig{client_id: "lightning"}] = Repo.all(AuthConfig)
    end
  end

  describe "setting up" do
    test "fetches the discovery document, saves the provider and answers 201",
         ctx do
      expect_wellknown(ctx.bypass)

      conn =
        put(superuser_conn(), ~p"/api/auth_provider", %{
          "name" => ctx.name,
          "discovery_url" => ctx.discovery_url,
          "client_id" => "lightning",
          "client_secret" => "s3cret"
        })

      provider = AuthProviders.get_existing()
      assert json_response(conn, 201) == %{"data" => provider_body(provider)}

      assert %AuthConfig{
               client_secret: "s3cret",
               allow_unverified_email: false
             } = provider

      assert provider.redirect_uri == redirect_uri(ctx.name)
    end

    test "refuses missing fields, a bad name and any other key, without fetching anything",
         ctx do
      for {body, entries} <- [
            {%{},
             [
               %{
                 "pointer" => "#/name",
                 "code" => "required",
                 "detail" => "can't be blank"
               },
               %{
                 "pointer" => "#/discovery_url",
                 "code" => "required",
                 "detail" => "can't be blank"
               },
               %{
                 "pointer" => "#/client_id",
                 "code" => "required",
                 "detail" => "can't be blank"
               },
               %{
                 "pointer" => "#/client_secret",
                 "code" => "required",
                 "detail" => "can't be blank"
               }
             ]},
            {%{
               "name" => "Not Lower",
               "discovery_url" => ctx.discovery_url,
               "client_id" => "lightning",
               "client_secret" => "s3cret",
               "allow_unverified_email" => true
             },
             [
               %{
                 "pointer" => "#/name",
                 "code" => "format",
                 "detail" =>
                   "must be lower-case and only contain alphanumeric, dash and underscore characters"
               },
               %{
                 "pointer" => "#/allow_unverified_email",
                 "code" => "unknown_key",
                 "detail" => "is not accepted"
               }
             ]}
          ] do
        superuser_conn()
        |> put(~p"/api/auth_provider", body)
        |> assert_problem(422, :invalid, entries)
      end

      assert Repo.all(AuthConfig) == []
    end

    test "refuses a body that isn't an object with malformed" do
      superuser_conn()
      |> put(~p"/api/auth_provider", "[1]")
      |> assert_problem(400, :malformed, [])
    end

    test "refuses a discovery document that can't be read, lacks an endpoint, or isn't served over HTTPS",
         ctx do
      Bypass.expect_once(ctx.bypass, "GET", "/auth/unreadable", fn conn ->
        Plug.Conn.resp(conn, 404, "")
      end)

      Bypass.expect_once(ctx.bypass, "GET", "/auth/no-token", fn conn ->
        wellknown = Map.delete(build_wellknown(ctx.bypass), "token_endpoint")
        Plug.Conn.resp(conn, 200, Jason.encode!(wellknown))
      end)

      base = "http://localhost:#{ctx.bypass.port}/auth"

      for {url, entry} <- [
            {base <> "/unreadable",
             %{
               "code" => "discovery_failed",
               "detail" => "error parsing .well-known"
             }},
            {base <> "/no-token",
             %{
               "code" => "discovery_failed",
               "detail" =>
                 "Provider expects a WellKnown struct with a 'token_endpoint' key."
             }},
            {"http://sso.example.org/.well-known",
             %{
               "code" => "format",
               "detail" => "discovery endpoint must use https"
             }}
          ] do
        superuser_conn()
        |> put(~p"/api/auth_provider", %{
          "name" => ctx.name,
          "discovery_url" => url,
          "client_id" => "lightning",
          "client_secret" => "s3cret"
        })
        |> assert_problem(422, :invalid, [
          Map.put(entry, "pointer", "#/discovery_url")
        ])
      end

      assert Repo.all(AuthConfig) == []
    end
  end

  describe "replacing" do
    test "keeps the stored secret when none is sent, renames, and answers 200",
         ctx do
      insert_provider(ctx)
      expect_wellknown(ctx.bypass)
      new_name = ctx.name <> "-renamed"
      on_exit(fn -> AuthProviders.remove_handler(new_name) end)

      conn =
        put(superuser_conn(), ~p"/api/auth_provider", %{
          "name" => new_name,
          "discovery_url" => ctx.discovery_url,
          "client_id" => "lightning-2"
        })

      provider = AuthProviders.get_existing()
      assert json_response(conn, 200) == %{"data" => provider_body(provider)}

      assert %AuthConfig{client_id: "lightning-2", client_secret: "kept-secret"} =
               provider

      assert provider.redirect_uri == redirect_uri(new_name)
      assert {:ok, %{name: ^new_name}} = AuthProviders.get_handler(new_name)
      assert {:error, :not_found} = AuthProviders.get_handler(ctx.name)
    end
  end

  describe "removing" do
    test "removes the provider and answers 204", ctx do
      insert_provider(ctx)

      conn = delete(superuser_conn(), ~p"/api/auth_provider")

      assert conn.status == 204
      assert conn.resp_body == ""
      assert Repo.all(AuthConfig) == []
      assert {:error, :not_found} = AuthProviders.get_handler(ctx.name)
    end

    test "answers not_found when none is set up" do
      superuser_conn()
      |> delete(~p"/api/auth_provider")
      |> assert_problem(404, :not_found, [])
    end
  end

  describe "stale writes" do
    test "a replace while another request removes the provider answers concurrent_edit",
         ctx do
      provider = insert_provider(ctx)

      # Another request removes it while the discovery document is fetched.
      Bypass.expect_once(ctx.bypass, "GET", "/auth/.well-known", fn conn ->
        Repo.delete!(provider)
        Plug.Conn.resp(conn, 200, Jason.encode!(build_wellknown(ctx.bypass)))
      end)

      superuser_conn()
      |> put(~p"/api/auth_provider", %{
        "name" => ctx.name,
        "discovery_url" => ctx.discovery_url,
        "client_id" => "lightning-2"
      })
      |> assert_problem(409, :concurrent_edit, [])

      assert Repo.all(AuthConfig) == []
    end

    test "a removal after another request removed the provider answers concurrent_edit",
         ctx do
      provider = insert_provider(ctx)
      test_pid = self()
      handler = {__MODULE__, make_ref()}

      :telemetry.attach(
        handler,
        [:lightning, :repo, :query],
        fn _event, _measurements, meta, _config ->
          if self() == test_pid and meta.source == "auth_providers" and
               String.starts_with?(meta.query, "SELECT") do
            :telemetry.detach(handler)

            Repo.query!("DELETE FROM auth_providers WHERE id = $1", [
              Ecto.UUID.dump!(provider.id)
            ])
          end
        end,
        nil
      )

      on_exit(fn -> :telemetry.detach(handler) end)

      superuser_conn()
      |> delete(~p"/api/auth_provider")
      |> assert_problem(409, :concurrent_edit, [])

      assert Repo.all(AuthConfig) == []
    end
  end
end
