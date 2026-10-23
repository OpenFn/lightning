defmodule LightningWeb.ChannelProxyAuthTest do
  use LightningWeb.ConnCase, async: true

  alias Lightning.Channels.{ChannelRequest, ChannelEvent}

  import Ecto.Query
  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
  import LightningWeb.API.ChannelProxyHelpers
  import Plug.Test, only: [conn: 2]

  setup do
    bypass = Bypass.open()
    project = insert(:project)

    channel =
      insert(:channel,
        project: project,
        destination_url: "http://localhost:#{bypass.port}",
        enabled: true
      )

    disabled_channel =
      insert(:channel,
        project: project,
        destination_url: "http://localhost:#{bypass.port}",
        enabled: false
      )

    {:ok, bypass: bypass, channel: channel, disabled_channel: disabled_channel}
  end

  describe "client authentication" do
    test "no auth methods configured — request passes through", %{
      conn: conn,
      bypass: bypass,
      channel: channel
    } do
      # Channel has no channel_auth_methods, so it's publicly accessible
      Bypass.expect_once(bypass, "GET", "/open", fn conn ->
        Plug.Conn.send_resp(conn, 200, "public")
      end)

      resp = get(conn, "/channels/#{channel.id}/open")

      assert resp.status == 200
      assert resp.resp_body == "public"
    end

    test "API key auth — correct key allows request", %{
      bypass: bypass
    } do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :api, api_key: "valid-api-key"}
        ])

      Bypass.expect_once(bypass, "GET", "/protected", fn conn ->
        Plug.Conn.send_resp(conn, 200, "authenticated")
      end)

      resp =
        conn(:get, "/channels/#{channel.id}/protected")
        |> put_req_header("x-api-key", "valid-api-key")
        |> send_to_endpoint()

      assert resp.status == 200
      assert resp.resp_body == "authenticated"
    end

    test "API key auth — wrong key returns 401", %{bypass: bypass} do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :api, api_key: "correct-key"}
        ])

      resp =
        conn(:get, "/channels/#{channel.id}/protected")
        |> put_req_header("x-api-key", "wrong-key")
        |> send_to_endpoint()

      assert_unauthenticated(resp, :unauthenticated, [
        ~s(ApiKey header="x-api-key")
      ])
    end

    test "API key auth — no key sent returns 401", %{bypass: bypass} do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :api, api_key: "some-key"}
        ])

      resp =
        conn(:get, "/channels/#{channel.id}/protected")
        |> send_to_endpoint()

      assert_unauthenticated(resp, :unauthenticated, [
        ~s(ApiKey header="x-api-key")
      ])
    end

    test "Basic auth — correct credentials allows request", %{bypass: bypass} do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :basic, username: "admin", password: "secret"}
        ])

      Bypass.expect_once(bypass, "GET", "/basic", fn conn ->
        Plug.Conn.send_resp(conn, 200, "basic-ok")
      end)

      encoded = Base.encode64("admin:secret")

      resp =
        conn(:get, "/channels/#{channel.id}/basic")
        |> put_req_header("authorization", "Basic #{encoded}")
        |> send_to_endpoint()

      assert resp.status == 200
      assert resp.resp_body == "basic-ok"
    end

    test "Basic auth — wrong credentials returns 401", %{bypass: bypass} do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :basic, username: "admin", password: "secret"}
        ])

      encoded = Base.encode64("admin:wrong")

      resp =
        conn(:get, "/channels/#{channel.id}/basic")
        |> put_req_header("authorization", "Basic #{encoded}")
        |> send_to_endpoint()

      assert_unauthenticated(resp, :unauthenticated, [])
    end

    test "Basic auth — no auth header returns 401 with no Basic challenge, so no browser prompts for a login it could send to other channels",
         %{bypass: bypass} do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :basic, username: "admin", password: "secret"}
        ])

      resp =
        conn(:get, "/channels/#{channel.id}")
        |> send_to_endpoint()

      assert_unauthenticated(resp, :unauthenticated, [])
    end

    test "multiple auth methods — either matches allows request", %{
      bypass: bypass
    } do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :api, api_key: "key-one"},
          %{auth_type: :api, api_key: "key-two"}
        ])

      Bypass.expect_once(bypass, "GET", "/multi", fn conn ->
        Plug.Conn.send_resp(conn, 200, "multi-ok")
      end)

      # Use the second key — should still match
      resp =
        conn(:get, "/channels/#{channel.id}/multi")
        |> put_req_header("x-api-key", "key-two")
        |> send_to_endpoint()

      assert resp.status == 200
      assert resp.resp_body == "multi-ok"
    end

    test "mixed types (API + Basic) — API key matches allows request", %{
      bypass: bypass
    } do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :api, api_key: "mixed-key"},
          %{auth_type: :basic, username: "user", password: "pass"}
        ])

      Bypass.expect_once(bypass, "GET", "/mixed", fn conn ->
        Plug.Conn.send_resp(conn, 200, "mixed-ok")
      end)

      resp =
        conn(:get, "/channels/#{channel.id}/mixed")
        |> put_req_header("x-api-key", "mixed-key")
        |> send_to_endpoint()

      assert resp.status == 200
      assert resp.resp_body == "mixed-ok"
    end

    test "mixed types (API + Basic) — no credentials challenges only the API key",
         %{bypass: bypass} do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :api, api_key: "mixed-key"},
          %{auth_type: :basic, username: "user", password: "pass"}
        ])

      resp =
        conn(:get, "/channels/#{channel.id}/mixed")
        |> send_to_endpoint()

      assert_unauthenticated(resp, :unauthenticated, [
        ~s(ApiKey header="x-api-key")
      ])
    end

    test "revoked API key (scheduled for deletion) returns 401",
         %{bypass: bypass} do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :api, api_key: "live-key"},
          %{auth_type: :api, api_key: "revoked-key"}
        ])

      revoke_client_auth_method(channel, "revoked-key")

      # A stub, not an expectation: if the revoked credential is accepted the
      # request reaches the destination and this responds 200.
      Bypass.stub(bypass, "GET", "/protected", fn conn ->
        Plug.Conn.send_resp(conn, 200, "proxied-with-revoked-credential")
      end)

      resp =
        conn(:get, "/channels/#{channel.id}/protected")
        |> put_req_header("x-api-key", "revoked-key")
        |> send_to_endpoint()

      assert_unauthenticated(resp, :unauthenticated, [
        ~s(ApiKey header="x-api-key")
      ])
    end

    test "revoked basic credentials (scheduled for deletion) return 401",
         %{bypass: bypass} do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :api, api_key: "live-key"},
          %{auth_type: :basic, username: "partner", password: "revoked-pass"}
        ])

      revoke_client_auth_method(channel, fn wam -> wam.auth_type == :basic end)

      # A stub, not an expectation: if the revoked credential is accepted the
      # request reaches the destination and this responds 200.
      Bypass.stub(bypass, "GET", "/protected", fn conn ->
        Plug.Conn.send_resp(conn, 200, "proxied-with-revoked-credential")
      end)

      encoded = Base.encode64("partner:revoked-pass")

      resp =
        conn(:get, "/channels/#{channel.id}/protected")
        |> put_req_header("authorization", "Basic #{encoded}")
        |> send_to_endpoint()

      assert_unauthenticated(resp, :unauthenticated, [
        ~s(ApiKey header="x-api-key")
      ])
    end

    test "the remaining live key still authenticates after another is revoked",
         %{bypass: bypass} do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :api, api_key: "live-key"},
          %{auth_type: :api, api_key: "revoked-key"}
        ])

      revoke_client_auth_method(channel, "revoked-key")

      Bypass.expect_once(bypass, "GET", "/protected", fn conn ->
        Plug.Conn.send_resp(conn, 200, "authenticated")
      end)

      resp =
        conn(:get, "/channels/#{channel.id}/protected")
        |> put_req_header("x-api-key", "live-key")
        |> send_to_endpoint()

      assert resp.status == 200
      assert resp.resp_body == "authenticated"
    end

    # Severing the join rows at delete time revokes the credential immediately,
    # but a channel left with no client method authenticates nobody and keeps
    # forwarding with its destination credential. That is #387, not a
    # regression introduced here; this test pins the behaviour so the gap is
    # visible in the suite rather than implied. Delete it when #387 lands.
    test "revoking a channel's only client method opens it to anonymous callers",
         %{bypass: bypass} do
      project = insert(:project)
      user = insert(:user)

      credential =
        insert(:credential,
          schema: "@openfn/language-http",
          name: "destination-cred",
          user: user
        )
        |> with_body(%{body: %{"access_token" => "dest-token-xyz"}})

      project_credential =
        insert(:project_credential, project: project, credential: credential)

      channel =
        insert(:channel,
          project: project,
          destination_url: "http://localhost:#{bypass.port}",
          enabled: true,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :client,
              webhook_auth_method:
                build(:webhook_auth_method,
                  project: project,
                  auth_type: :api,
                  api_key: "only-key"
                )
            ),
            build(:channel_auth_method,
              role: :destination,
              webhook_auth_method: nil,
              project_credential: project_credential
            )
          ]
        )

      revoke_client_auth_method(channel, "only-key")

      Bypass.expect_once(bypass, "GET", "/protected", fn conn ->
        assert Plug.Conn.get_req_header(conn, "authorization") == [
                 "Bearer dest-token-xyz"
               ],
               "the destination credential is still spent on an unauthenticated caller"

        Plug.Conn.send_resp(conn, 200, "anonymous")
      end)

      resp =
        conn(:get, "/channels/#{channel.id}/protected")
        |> send_to_endpoint()

      assert resp.status == 200
      assert resp.resp_body == "anonymous"
    end

    defp revoke_client_auth_method(channel, api_key) when is_binary(api_key) do
      revoke_client_auth_method(channel, fn wam -> wam.api_key == api_key end)
    end

    defp revoke_client_auth_method(channel, matcher) when is_function(matcher) do
      auth_method =
        channel.channel_auth_methods
        |> Enum.map(& &1.webhook_auth_method)
        |> Enum.reject(&is_nil/1)
        |> Enum.find(matcher)

      {:ok, _} =
        Lightning.WebhookAuthMethods.schedule_for_deletion(auth_method,
          actor: insert(:user)
        )
    end
  end

  describe "destination authentication" do
    test "Bearer token sent to upstream when channel has http credential with access_token",
         %{bypass: bypass} do
      channel =
        create_destination_auth_channel(bypass, "@openfn/language-http", %{
          "access_token" => "tok-123"
        })

      Bypass.expect_once(bypass, "GET", "/test", fn conn ->
        auth = Plug.Conn.get_req_header(conn, "authorization")
        assert auth == ["Bearer tok-123"]
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      resp =
        conn(:get, "/channels/#{channel.id}/test")
        |> send_to_endpoint()

      assert resp.status == 200
    end

    test "Basic auth sent when channel has http credential with username/password",
         %{bypass: bypass} do
      channel =
        create_destination_auth_channel(bypass, "@openfn/language-http", %{
          "username" => "u",
          "password" => "p"
        })

      expected = "Basic #{Base.encode64("u:p")}"

      Bypass.expect_once(bypass, "GET", "/test", fn conn ->
        auth = Plug.Conn.get_req_header(conn, "authorization")
        assert auth == [expected]
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      resp =
        conn(:get, "/channels/#{channel.id}/test")
        |> send_to_endpoint()

      assert resp.status == 200
    end

    test "ApiToken sent when channel has dhis2 credential with pat",
         %{bypass: bypass} do
      channel =
        create_destination_auth_channel(bypass, "@openfn/language-dhis2", %{
          "pat" => "d2pat_abc"
        })

      Bypass.expect_once(bypass, "GET", "/test", fn conn ->
        auth = Plug.Conn.get_req_header(conn, "authorization")
        assert auth == ["ApiToken d2pat_abc"]
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      resp =
        conn(:get, "/channels/#{channel.id}/test")
        |> send_to_endpoint()

      assert resp.status == 200
    end

    test "no authorization header when channel has no destination auth method",
         %{bypass: bypass, channel: channel} do
      Bypass.expect_once(bypass, "GET", "/test", fn conn ->
        auth = Plug.Conn.get_req_header(conn, "authorization")
        assert auth == []
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      resp =
        conn(:get, "/channels/#{channel.id}/test")
        |> send_to_endpoint()

      assert resp.status == 200
    end

    test "authorization header redacted in persisted ChannelEvent",
         %{bypass: bypass} do
      channel =
        create_destination_auth_channel(bypass, "@openfn/language-http", %{
          "access_token" => "secret-token"
        })

      Bypass.expect_once(bypass, "GET", "/redact-test", fn conn ->
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      resp =
        conn(:get, "/channels/#{channel.id}/redact-test")
        |> send_to_endpoint()

      assert resp.status == 200

      event =
        Lightning.Repo.one!(
          from(e in ChannelEvent,
            join: r in ChannelRequest,
            on: r.id == e.channel_request_id,
            where: r.channel_id == ^channel.id
          )
        )

      # The handler redacts authorization headers before persisting
      # Headers are native jsonb arrays, no JSON decoding needed
      auth_header =
        Enum.find(event.request_headers, fn [k, _v] -> k == "authorization" end)

      assert auth_header == ["authorization", "[REDACTED]"]
    end

    test "credential environment_not_found returns 502 with observable error",
         %{bypass: bypass} do
      # Create a credential with NO credential_body for "main" environment
      project = insert(:project)
      user = insert(:user)

      credential =
        insert(:credential,
          schema: "@openfn/language-http",
          name: "no-body",
          user: user
        )

      # Don't call with_body — no CredentialBody exists

      project_credential =
        insert(:project_credential,
          project: project,
          credential: credential
        )

      channel =
        insert(:channel,
          project: project,
          destination_url: "http://localhost:#{bypass.port}",
          enabled: true,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :destination,
              webhook_auth_method: nil,
              project_credential: project_credential
            )
          ]
        )

      resp =
        conn(:get, "/channels/#{channel.id}/test")
        |> send_to_endpoint()

      assert_problem(resp, 502, :bad_gateway, [])

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert request.state == :error

      event =
        Lightning.Repo.one!(
          from(e in ChannelEvent, where: e.channel_request_id == ^request.id)
        )

      assert event.error_message == "credential_environment_not_found"
    end

    test "a sandbox authenticates with its own environment, not the parent's",
         %{bypass: bypass} do
      # The bug this PR fixes: the proxy asked for "main" whatever project it
      # was acting for, so a sandbox reached its destination holding the
      # parent's production secret. Reverting the fix has to fail here.
      root = insert(:project)
      sandbox = insert(:project, parent: root, env: "staging")
      user = insert(:user)

      credential =
        insert(:credential,
          schema: "@openfn/language-http",
          name: "shared",
          user: user
        )
        |> with_body(%{
          name: "main",
          body: %{"username" => "prod", "password" => "prod-secret"}
        })
        |> with_body(%{
          name: "staging",
          body: %{"username" => "sbx", "password" => "sbx-secret"}
        })

      project_credential =
        insert(:project_credential, project: sandbox, credential: credential)

      channel =
        insert(:channel,
          project: sandbox,
          destination_url: "http://localhost:#{bypass.port}",
          enabled: true,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :destination,
              webhook_auth_method: nil,
              project_credential: project_credential
            )
          ]
        )

      sandbox_auth = "Basic #{Base.encode64("sbx:sbx-secret")}"
      parent_auth = "Basic #{Base.encode64("prod:prod-secret")}"

      Bypass.expect_once(bypass, "GET", "/test", fn conn ->
        auth = Plug.Conn.get_req_header(conn, "authorization")
        assert auth == [sandbox_auth]
        refute auth == [parent_auth]
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      resp =
        conn(:get, "/channels/#{channel.id}/test")
        |> send_to_endpoint()

      assert resp.status == 200
    end

    test "a sandbox with no environment set returns 502 with observable error",
         %{bypass: bypass} do
      # Deriving the environment instead of assuming "main" gave this path two
      # new failure reasons. They have to land as a recorded 502 like every
      # other credential error, not as an unhandled crash.
      root = insert(:project)
      sandbox = insert(:project, parent: root, env: nil)
      user = insert(:user)

      credential =
        insert(:credential,
          schema: "@openfn/language-http",
          name: "parent",
          user: user
        )

      project_credential =
        insert(:project_credential, project: sandbox, credential: credential)

      channel =
        insert(:channel,
          project: sandbox,
          destination_url: "http://localhost:#{bypass.port}",
          enabled: true,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :destination,
              webhook_auth_method: nil,
              project_credential: project_credential
            )
          ]
        )

      resp =
        conn(:get, "/channels/#{channel.id}/test")
        |> send_to_endpoint()

      assert_problem(resp, 502, :bad_gateway, [])

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert request.state == :error

      event =
        Lightning.Repo.one!(
          from(e in ChannelEvent, where: e.channel_request_id == ^request.id)
        )

      assert event.error_message == "credential_environment_not_configured"
    end

    test "credential with missing auth fields returns 502 with observable error",
         %{bypass: bypass} do
      channel =
        create_destination_auth_channel(bypass, "@openfn/language-http", %{
          "baseUrl" => "https://example.com"
        })

      resp =
        conn(:get, "/channels/#{channel.id}/test")
        |> send_to_endpoint()

      assert_problem(resp, 502, :bad_gateway, [])

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert request.state == :error

      event =
        Lightning.Repo.one!(
          from(e in ChannelEvent, where: e.channel_request_id == ^request.id)
        )

      assert event.error_message == "credential_missing_auth_fields"
    end

    test "a credential error whose snapshot can't be saved answers 502 bad_gateway",
         %{bypass: bypass} do
      channel =
        create_destination_auth_channel(bypass, "@openfn/language-http", %{
          "baseUrl" => "https://example.com"
        })

      unsnapshottable!(channel)

      resp =
        conn(:get, "/channels/#{channel.id}/test")
        |> send_to_endpoint()

      assert_problem(resp, 502, :bad_gateway, [])

      refute Lightning.Repo.exists?(
               from(r in ChannelRequest, where: r.channel_id == ^channel.id)
             )
    end

    test "proxy headers (x-forwarded-*) still forwarded alongside auth header",
         %{bypass: bypass} do
      channel =
        create_destination_auth_channel(bypass, "@openfn/language-http", %{
          "access_token" => "tok-with-proxy"
        })

      Bypass.expect_once(bypass, "GET", "/test", fn conn ->
        auth = Plug.Conn.get_req_header(conn, "authorization")
        xff = Plug.Conn.get_req_header(conn, "x-forwarded-for")
        xfh = Plug.Conn.get_req_header(conn, "x-forwarded-host")
        xfp = Plug.Conn.get_req_header(conn, "x-forwarded-proto")

        assert auth == ["Bearer tok-with-proxy"]
        assert xff != []
        assert xfh != []
        assert xfp != []

        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      resp =
        conn(:get, "/channels/#{channel.id}/test")
        |> send_to_endpoint()

      assert resp.status == 200
    end
  end
end
