defmodule LightningWeb.ChannelProxyPlugTest do
  use LightningWeb.ConnCase, async: true

  alias Lightning.Channels.{ChannelRequest, ChannelEvent}

  import Ecto.Query
  import Lightning.Factories
  import Plug.Test, only: [conn: 2, conn: 3]

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

  describe "proxying requests" do
    test "GET proxied to destination with correct path", %{
      conn: conn,
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "GET", "/test", fn conn ->
        Plug.Conn.send_resp(conn, 200, "ok from destination")
      end)

      resp = get(conn, "/channels/#{channel.id}/test")

      assert resp.status == 200
      assert resp.resp_body == "ok from destination"
    end

    test "POST with body arrives at destination unchanged", %{
      bypass: bypass,
      channel: channel
    } do
      body = Jason.encode!(%{"hello" => "world"})

      Bypass.expect_once(bypass, "POST", "/api/data", fn conn ->
        {:ok, received, conn} = Plug.Conn.read_body(conn)
        assert received == body
        Plug.Conn.send_resp(conn, 201, "created")
      end)

      resp =
        conn(:post, "/channels/#{channel.id}/api/data", body)
        |> put_req_header("content-type", "application/json")
        |> put_req_header("content-length", "#{byte_size(body)}")
        |> send_to_endpoint()

      assert resp.status == 201
      assert resp.resp_body == "created"
    end

    test "PUT method forwarded", %{
      conn: conn,
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "PUT", "/resource", fn conn ->
        Plug.Conn.send_resp(conn, 200, "updated")
      end)

      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> put("/channels/#{channel.id}/resource", "{}")

      assert resp.status == 200
    end

    test "PATCH method forwarded", %{
      conn: conn,
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "PATCH", "/resource", fn conn ->
        Plug.Conn.send_resp(conn, 200, "patched")
      end)

      resp =
        conn
        |> put_req_header("content-type", "application/json")
        |> patch("/channels/#{channel.id}/resource", "{}")

      assert resp.status == 200
    end

    test "DELETE method forwarded", %{
      conn: conn,
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "DELETE", "/resource", fn conn ->
        Plug.Conn.send_resp(conn, 204, "")
      end)

      resp = delete(conn, "/channels/#{channel.id}/resource")

      assert resp.status == 204
    end

    test "query parameters preserved", %{
      conn: conn,
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "GET", "/search", fn conn ->
        assert conn.query_string == "q=foo&page=2"
        Plug.Conn.send_resp(conn, 200, "results")
      end)

      resp = get(conn, "/channels/#{channel.id}/search?q=foo&page=2")

      assert resp.status == 200
    end

    test "nested path forwarded correctly", %{
      conn: conn,
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "GET", "/nested/path/here", fn conn ->
        Plug.Conn.send_resp(conn, 200, "deep")
      end)

      resp = get(conn, "/channels/#{channel.id}/nested/path/here")

      assert resp.status == 200
    end

    test "path traversal in channel_id position fails UUID validation", %{
      conn: conn
    } do
      # A path like /channels/../../secret would have ".." as channel_id,
      # which fails Ecto.UUID.cast and returns 404.
      resp = get(conn, "/channels/../../secret")

      assert resp.status == 404
    end

    test "path traversal segments in subpath are forwarded as-is", %{
      conn: conn,
      bypass: bypass,
      channel: channel
    } do
      # In production, HTTP clients (browsers) normalize "../" segments
      # before sending the request, so they never reach the server.
      # If they do arrive (e.g. from a programmatic client), they are
      # forwarded to the upstream as-is — the upstream is responsible
      # for its own path handling.
      Bypass.expect_once(bypass, "GET", "/foo/../safe", fn conn ->
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      resp = get(conn, "/channels/#{channel.id}/foo/../safe")

      assert resp.status == 200
    end

    test "root path (no trailing path) proxies to /", %{
      conn: conn,
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "GET", "/", fn conn ->
        Plug.Conn.send_resp(conn, 200, "root")
      end)

      resp = get(conn, "/channels/#{channel.id}")

      assert resp.status == 200
      assert resp.resp_body == "root"
    end

    test "trailing slash on destination_url does not produce double slash", %{
      bypass: bypass
    } do
      project = insert(:project)

      channel =
        insert(:channel,
          project: project,
          destination_url: "http://localhost:#{bypass.port}/",
          enabled: true
        )

      Bypass.expect_once(bypass, "GET", "/", fn conn ->
        Plug.Conn.send_resp(conn, 200, "root")
      end)

      resp =
        conn(:get, "/channels/#{channel.id}")
        |> send_to_endpoint()

      assert resp.status == 200
      assert resp.resp_body == "root"
    end

    test "trailing slash on destination_url with subpath", %{bypass: bypass} do
      project = insert(:project)

      channel =
        insert(:channel,
          project: project,
          destination_url: "http://localhost:#{bypass.port}/",
          enabled: true
        )

      Bypass.expect_once(bypass, "GET", "/api/data", fn conn ->
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      resp =
        conn(:get, "/channels/#{channel.id}/api/data")
        |> send_to_endpoint()

      assert resp.status == 200
    end

    test "proxy headers forwarded to destination", %{
      conn: conn,
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "GET", "/test", fn conn ->
        xff = Plug.Conn.get_req_header(conn, "x-forwarded-for")
        xfh = Plug.Conn.get_req_header(conn, "x-forwarded-host")
        xfp = Plug.Conn.get_req_header(conn, "x-forwarded-proto")

        assert xff != []
        assert xfh != []
        assert xfp != []

        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      resp = get(conn, "/channels/#{channel.id}/test")

      assert resp.status == 200
    end

    test "x-request-id forwarded to destination", %{
      bypass: bypass,
      channel: channel
    } do
      test_pid = self()

      Bypass.expect_once(bypass, "GET", "/trace", fn conn ->
        [received_id] = Plug.Conn.get_req_header(conn, "x-request-id")
        send(test_pid, {:destination_request_id, received_id})
        Plug.Conn.send_resp(conn, 200, "traced")
      end)

      resp =
        conn(:get, "/channels/#{channel.id}/trace")
        |> send_to_endpoint()

      assert resp.status == 200

      [response_id] = Plug.Conn.get_resp_header(resp, "x-request-id")
      assert_receive {:destination_request_id, ^response_id}
    end

    test "response headers from destination forwarded to client", %{
      conn: conn,
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "GET", "/test", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("x-custom-header", "custom-value")
        |> Plug.Conn.send_resp(200, "ok")
      end)

      resp = get(conn, "/channels/#{channel.id}/test")

      assert resp.status == 200

      assert Plug.Conn.get_resp_header(resp, "x-custom-header") == [
               "custom-value"
             ]
    end

    test "host header sent to destination matches upstream URL, not client's original host",
         %{bypass: bypass, channel: channel} do
      test_pid = self()

      Bypass.expect_once(bypass, "GET", "/host-check", fn conn ->
        [received_host] = Plug.Conn.get_req_header(conn, "host")
        send(test_pid, {:destination_host, received_host})
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      # Simulate a real HTTP request with an attacker-controlled host header.
      # In production, Cowboy always includes the client's Host header in
      # req_headers; Plug.Test.conn does not, so we inject it manually.
      base_conn = conn(:get, "/channels/#{channel.id}/host-check")

      resp =
        %{
          base_conn
          | host: "evil.example.com",
            req_headers: [
              {"host", "evil.example.com"} | base_conn.req_headers
            ]
        }
        |> send_to_endpoint()

      assert resp.status == 200

      assert_receive {:destination_host, received_host}
      assert received_host == "localhost:#{bypass.port}"
    end
  end

  describe "error cases" do
    test "disabled channel returns 404", %{
      conn: conn,
      disabled_channel: disabled_channel
    } do
      resp = get(conn, "/channels/#{disabled_channel.id}/test")

      assert resp.status == 404
      assert %{"error" => "Not Found"} = json_response(resp, 404)
    end

    test "non-existent channel returns 404", %{conn: conn} do
      resp = get(conn, "/channels/#{Ecto.UUID.generate()}/test")

      assert %{"error" => "Not Found"} = json_response(resp, 404)
    end

    test "invalid UUID returns 404", %{conn: conn} do
      resp = get(conn, "/channels/not-a-uuid/test")

      assert %{"error" => "Not Found"} = json_response(resp, 404)
    end

    test "destination timeout returns 502", %{
      conn: conn,
      channel: channel
    } do
      # Channel's destination_url points to a port with nothing running
      port = Enum.random(59_000..59_999)

      channel
      |> Ecto.Changeset.change(destination_url: "http://localhost:#{port}")
      |> Lightning.Repo.update!()

      resp = get(conn, "/channels/#{channel.id}/test")

      assert resp.status in [502, 504]
    end
  end

  describe "handler persistence" do
    test "creates ChannelRequest and ChannelEvent on successful proxy", %{
      conn: conn,
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "GET", "/persisted", fn conn ->
        Plug.Conn.send_resp(conn, 200, "persisted response")
      end)

      resp = get(conn, "/channels/#{channel.id}/persisted")
      assert resp.status == 200

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert request.state == :success
      assert request.completed_at != nil

      event =
        Lightning.Repo.one!(
          from(e in ChannelEvent, where: e.channel_request_id == ^request.id)
        )

      assert event.type == :destination_response
      assert event.response_status == 200
      assert event.latency_us != nil
      assert event.request_method == "GET"
      assert event.request_path == "/persisted"
    end

    test "creates error-state request on connection failure", %{
      conn: conn,
      channel: channel
    } do
      port = Enum.random(59_000..59_999)

      channel
      |> Ecto.Changeset.change(destination_url: "http://localhost:#{port}")
      |> Lightning.Repo.update!()

      resp = get(conn, "/channels/#{channel.id}/fail")
      assert resp.status in [502, 504]

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert request.state in [:error, :timeout]
      assert request.completed_at != nil
    end
  end

  describe "client authentication" do
    defp create_client_auth_channel(bypass, auth_method_specs) do
      project = insert(:project)

      channel_auth_methods =
        Enum.map(auth_method_specs, fn spec ->
          build(:channel_auth_method,
            role: :client,
            webhook_auth_method:
              build(
                :webhook_auth_method,
                [project: project] ++ Enum.to_list(spec)
              )
          )
        end)

      insert(:channel,
        project: project,
        destination_url: "http://localhost:#{bypass.port}",
        enabled: true,
        channel_auth_methods: channel_auth_methods
      )
    end

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

      assert resp.status == 401
      assert %{"error" => "Unauthorized"} = json_response(resp, 401)
    end

    test "API key auth — no key sent returns 401", %{bypass: bypass} do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :api, api_key: "some-key"}
        ])

      resp =
        conn(:get, "/channels/#{channel.id}/protected")
        |> send_to_endpoint()

      assert resp.status == 401
      assert %{"error" => "Unauthorized"} = json_response(resp, 401)
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

      assert resp.status == 401
      assert %{"error" => "Unauthorized"} = json_response(resp, 401)
    end

    test "Basic auth — no auth header returns 401", %{bypass: bypass} do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :basic, username: "admin", password: "secret"}
        ])

      resp =
        conn(:get, "/channels/#{channel.id}/basic")
        |> send_to_endpoint()

      assert resp.status == 401
      assert %{"error" => "Unauthorized"} = json_response(resp, 401)
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
  end

  describe "client auth header stripping" do
    test "strips x-api-key header when client uses API key auth", %{
      bypass: bypass
    } do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :api, api_key: "valid-api-key"}
        ])

      Bypass.expect_once(bypass, "GET", "/test", fn conn ->
        api_key = Plug.Conn.get_req_header(conn, "x-api-key")

        assert api_key == [],
               "x-api-key should not be forwarded to the destination"

        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      conn(:get, "/channels/#{channel.id}/test")
      |> put_req_header("x-api-key", "valid-api-key")
      |> send_to_endpoint()
    end

    test "strips authorization header when client uses Basic auth", %{
      bypass: bypass
    } do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :basic, username: "admin", password: "secretpw"}
        ])

      encoded = Base.encode64("admin:secretpw")

      Bypass.expect_once(bypass, "GET", "/test", fn conn ->
        auth = Plug.Conn.get_req_header(conn, "authorization")

        assert auth == [],
               "client Basic auth should not be forwarded to the destination"

        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      conn(:get, "/channels/#{channel.id}/test")
      |> put_req_header("authorization", "Basic #{encoded}")
      |> send_to_endpoint()
    end

    test "replaces client Basic auth with destination Bearer auth", %{
      bypass: bypass
    } do
      project = insert(:project)
      user = insert(:user)

      credential =
        insert(:credential, schema: "http", name: "destination-cred", user: user)
        |> with_body(%{body: %{"access_token" => "dest-token-xyz"}})

      project_credential =
        insert(:project_credential,
          project: project,
          credential: credential
        )

      client_encoded = Base.encode64("user:password")

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
                  auth_type: :basic,
                  username: "user",
                  password: "password"
                )
            ),
            build(:channel_auth_method,
              role: :destination,
              webhook_auth_method: nil,
              project_credential: project_credential
            )
          ]
        )

      Bypass.expect_once(bypass, "GET", "/test", fn conn ->
        auth = Plug.Conn.get_req_header(conn, "authorization")

        assert auth == ["Bearer dest-token-xyz"],
               "destination should receive the destination Bearer token, not the client Basic auth"

        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      conn(:get, "/channels/#{channel.id}/test")
      |> put_req_header("authorization", "Basic #{client_encoded}")
      |> send_to_endpoint()
    end

    test "passes through client auth headers when no client auth configured",
         %{bypass: bypass, channel: channel} do
      Bypass.expect_once(bypass, "GET", "/test", fn conn ->
        auth = Plug.Conn.get_req_header(conn, "authorization")

        assert auth == ["Bearer client-token"],
               "client auth headers should pass through when no client auth is configured"

        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      conn(:get, "/channels/#{channel.id}/test")
      |> put_req_header("authorization", "Bearer client-token")
      |> send_to_endpoint()
    end
  end

  describe "destination authentication" do
    defp create_destination_auth_channel(bypass, schema, body) do
      project = insert(:project)
      user = insert(:user)

      credential =
        insert(:credential, schema: schema, name: "destination-cred", user: user)
        |> with_body(%{body: body})

      project_credential =
        insert(:project_credential,
          project: project,
          credential: credential
        )

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
    end

    test "Bearer token sent to upstream when channel has http credential with access_token",
         %{bypass: bypass} do
      channel =
        create_destination_auth_channel(bypass, "http", %{
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
        create_destination_auth_channel(bypass, "http", %{
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
        create_destination_auth_channel(bypass, "dhis2", %{
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
        create_destination_auth_channel(bypass, "http", %{
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
        insert(:credential, schema: "http", name: "no-body", user: user)

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

      assert resp.status == 502
      assert %{"error" => "Bad Gateway"} = json_response(resp, 502)

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

    test "credential with missing auth fields returns 502 with observable error",
         %{bypass: bypass} do
      channel =
        create_destination_auth_channel(bypass, "http", %{
          "baseUrl" => "https://example.com"
        })

      resp =
        conn(:get, "/channels/#{channel.id}/test")
        |> send_to_endpoint()

      assert resp.status == 502
      assert %{"error" => "Bad Gateway"} = json_response(resp, 502)

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

    test "proxy headers (x-forwarded-*) still forwarded alongside auth header",
         %{bypass: bypass} do
      channel =
        create_destination_auth_channel(bypass, "http", %{
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

  # ---------------------------------------------------------------
  # Phase 1a contract tests — query string + client auth tracking
  # ---------------------------------------------------------------
  #
  # These tests define the target interface after:
  # - D1: request_query_string on channel_events
  # - D3: client_webhook_auth_method_id and client_auth_type on channel_requests
  # - D4: Proxy plug passes query string and auth info into handler state
  #
  # They will not compile/pass until Phase 1b implements the changes.

  describe "query string persistence" do
    test "persists query string on channel event", %{
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "GET", "/search", fn conn ->
        Plug.Conn.send_resp(conn, 200, "results")
      end)

      conn(:get, "/channels/#{channel.id}/search?q=foo&page=2")
      |> send_to_endpoint()

      event =
        Lightning.Repo.one!(
          from(e in ChannelEvent,
            join: r in ChannelRequest,
            on: r.id == e.channel_request_id,
            where: r.channel_id == ^channel.id
          )
        )

      assert event.request_query_string == "q=foo&page=2"
    end

    test "empty query string when no params", %{
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "GET", "/plain", fn conn ->
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      conn(:get, "/channels/#{channel.id}/plain")
      |> send_to_endpoint()

      event =
        Lightning.Repo.one!(
          from(e in ChannelEvent,
            join: r in ChannelRequest,
            on: r.id == e.channel_request_id,
            where: r.channel_id == ^channel.id
          )
        )

      assert event.request_query_string == ""
    end
  end

  describe "client auth tracking" do
    test "persists auth method ID and type for API key auth", %{bypass: bypass} do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :api, api_key: "track-me"}
        ])

      auth_method =
        channel
        |> Lightning.Repo.preload(client_webhook_auth_methods: [])
        |> Map.get(:client_webhook_auth_methods)
        |> hd()

      Bypass.expect_once(bypass, "GET", "/tracked", fn conn ->
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      conn(:get, "/channels/#{channel.id}/tracked")
      |> put_req_header("x-api-key", "track-me")
      |> send_to_endpoint()

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert request.client_webhook_auth_method_id == auth_method.id
      assert request.client_auth_type == "api"
    end

    test "persists auth method ID and type for Basic auth", %{bypass: bypass} do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :basic, username: "user", password: "pass"}
        ])

      auth_method =
        channel
        |> Lightning.Repo.preload(client_webhook_auth_methods: [])
        |> Map.get(:client_webhook_auth_methods)
        |> hd()

      Bypass.expect_once(bypass, "GET", "/tracked", fn conn ->
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      encoded = Base.encode64("user:pass")

      conn(:get, "/channels/#{channel.id}/tracked")
      |> put_req_header("authorization", "Basic #{encoded}")
      |> send_to_endpoint()

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert request.client_webhook_auth_method_id == auth_method.id
      assert request.client_auth_type == "basic"
    end

    test "nil auth method when no client auth configured", %{
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "GET", "/open", fn conn ->
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      conn(:get, "/channels/#{channel.id}/open")
      |> send_to_endpoint()

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert request.client_webhook_auth_method_id == nil
      assert request.client_auth_type == nil
    end
  end

  describe "destination auth tracking" do
    test "persists destination_credential_id on successful proxy with destination auth",
         %{bypass: bypass} do
      channel =
        create_destination_auth_channel(bypass, "http", %{
          "access_token" => "tok-123"
        })

      project_credential_id =
        channel
        |> Lightning.Repo.preload(destination_auth_method: :project_credential)
        |> get_in([
          Access.key(:destination_auth_method),
          Access.key(:project_credential_id)
        ])

      Bypass.expect_once(bypass, "GET", "/dest-track", fn conn ->
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      conn(:get, "/channels/#{channel.id}/dest-track")
      |> send_to_endpoint()

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert request.destination_credential_id == project_credential_id
      refute is_nil(project_credential_id)
    end

    test "persists destination_credential_id even when credential resolution fails",
         %{bypass: _bypass} do
      # Channel with a destination auth method but credential missing auth
      # fields — destination auth resolution fails, but we still know which
      # credential was configured.
      project = insert(:project)
      user = insert(:user)

      credential =
        insert(:credential, schema: "http", name: "bad-cred", user: user)
        |> with_body(%{body: %{"baseUrl" => "https://example.com"}})

      project_credential =
        insert(:project_credential, project: project, credential: credential)

      channel =
        insert(:channel,
          project: project,
          destination_url: "http://localhost:9999",
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

      assert resp.status == 502

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert request.destination_credential_id == project_credential.id
      assert request.state == :error
    end

    test "destination_credential_id is nil when no destination auth configured",
         %{bypass: bypass, channel: channel} do
      Bypass.expect_once(bypass, "GET", "/no-dest-auth", fn conn ->
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      conn(:get, "/channels/#{channel.id}/no-dest-auth")
      |> send_to_endpoint()

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert request.destination_credential_id == nil
    end
  end

  describe "collect_timing integration" do
    test "persists per-direction timing after successful proxy", %{
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "GET", "/timed", fn conn ->
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      conn(:get, "/channels/#{channel.id}/timed")
      |> send_to_endpoint()

      event =
        Lightning.Repo.one!(
          from(e in ChannelEvent,
            join: r in ChannelRequest,
            on: r.id == e.channel_request_id,
            where: r.channel_id == ^channel.id
          )
        )

      # With collect_timing: true, Philter populates timing.send_us
      # which the handler persists as request_send_us
      assert is_integer(event.request_send_us)
      assert event.request_send_us >= 0
    end
  end

  defp send_to_endpoint(conn) do
    LightningWeb.Endpoint.call(conn, LightningWeb.Endpoint.init([]))
  end
end
