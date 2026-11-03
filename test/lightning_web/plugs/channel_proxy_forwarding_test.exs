defmodule LightningWeb.ChannelProxyForwardingTest do
  use LightningWeb.ConnCase, async: true

  import Lightning.Factories
  import LightningWeb.API.ChannelProxyHelpers
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

    test "strips the caller's session cookie before proxying to the destination",
         %{bypass: bypass, channel: channel} do
      test_pid = self()

      Bypass.expect_once(bypass, "GET", "/cookie-check", fn conn ->
        send(
          test_pid,
          {:destination_cookie, Plug.Conn.get_req_header(conn, "cookie")}
        )

        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      base_conn = conn(:get, "/channels/#{channel.id}/cookie-check")

      resp =
        %{
          base_conn
          | req_headers: [
              {"cookie", "_lightning_key=victim-session-token"}
              | base_conn.req_headers
            ]
        }
        |> send_to_endpoint()

      assert resp.status == 200
      assert_receive {:destination_cookie, []}
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
        insert(:credential,
          schema: "@openfn/language-http",
          name: "destination-cred",
          user: user
        )
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

    test "forwards x-api-key when no client auth configured",
         %{bypass: bypass, channel: channel} do
      headers =
        conn(:get, "/channels/#{channel.id}/test")
        |> put_req_header("x-api-key", "client-key")
        |> upstream_auth_headers(bypass)

      assert headers["x-api-key"] == ["client-key"]
    end

    test "forwards x-api-key and replaces authorization with the destination's when no client auth configured",
         %{bypass: bypass} do
      channel = create_client_auth_channel(bypass, [], "dest-token")

      headers =
        conn(:get, "/channels/#{channel.id}/test")
        |> put_req_header("authorization", "Bearer client-token")
        |> put_req_header("x-api-key", "client-key")
        |> upstream_auth_headers(bypass)

      assert headers["authorization"] == ["Bearer dest-token"]
      assert headers["x-api-key"] == ["client-key"]
    end

    test "forwards x-api-key when client uses Basic auth", %{bypass: bypass} do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :basic, username: "admin", password: "secretpw"}
        ])

      headers =
        conn(:get, "/channels/#{channel.id}/test")
        |> put_req_header(
          "authorization",
          "Basic #{Base.encode64("admin:secretpw")}"
        )
        |> put_req_header("x-api-key", "client-key")
        |> upstream_auth_headers(bypass)

      assert headers["x-api-key"] == ["client-key"]
    end

    test "forwards x-api-key when client uses Basic auth and the destination has auth",
         %{bypass: bypass} do
      channel =
        create_client_auth_channel(
          bypass,
          [%{auth_type: :basic, username: "admin", password: "secretpw"}],
          "dest-token"
        )

      headers =
        conn(:get, "/channels/#{channel.id}/test")
        |> put_req_header(
          "authorization",
          "Basic #{Base.encode64("admin:secretpw")}"
        )
        |> put_req_header("x-api-key", "client-key")
        |> upstream_auth_headers(bypass)

      assert headers["x-api-key"] == ["client-key"]
    end

    test "forwards authorization when client uses API key auth",
         %{bypass: bypass} do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :api, api_key: "valid-api-key"}
        ])

      headers =
        conn(:get, "/channels/#{channel.id}/test")
        |> put_req_header("x-api-key", "valid-api-key")
        |> put_req_header("authorization", "Bearer client-token")
        |> upstream_auth_headers(bypass)

      assert headers["authorization"] == ["Bearer client-token"]
    end

    test "strips x-api-key and replaces authorization with the destination's when client uses API key auth",
         %{bypass: bypass} do
      channel =
        create_client_auth_channel(
          bypass,
          [%{auth_type: :api, api_key: "valid-api-key"}],
          "dest-token"
        )

      headers =
        conn(:get, "/channels/#{channel.id}/test")
        |> put_req_header("x-api-key", "valid-api-key")
        |> put_req_header("authorization", "Bearer client-token")
        |> upstream_auth_headers(bypass)

      assert headers["authorization"] == ["Bearer dest-token"]
      assert headers["x-api-key"] == []
    end

    test "strips authorization and x-api-key when client has Basic and API key auth",
         %{bypass: bypass} do
      channel =
        create_client_auth_channel(bypass, [
          %{auth_type: :basic, username: "admin", password: "secretpw"},
          %{auth_type: :api, api_key: "valid-api-key"}
        ])

      headers =
        conn(:get, "/channels/#{channel.id}/test")
        |> put_req_header(
          "authorization",
          "Basic #{Base.encode64("admin:secretpw")}"
        )
        |> put_req_header("x-api-key", "valid-api-key")
        |> upstream_auth_headers(bypass)

      assert headers["authorization"] == []
      assert headers["x-api-key"] == []
    end

    test "strips x-api-key and replaces authorization with the destination's when client has Basic and API key auth",
         %{bypass: bypass} do
      channel =
        create_client_auth_channel(
          bypass,
          [
            %{auth_type: :basic, username: "admin", password: "secretpw"},
            %{auth_type: :api, api_key: "valid-api-key"}
          ],
          "dest-token"
        )

      headers =
        conn(:get, "/channels/#{channel.id}/test")
        |> put_req_header(
          "authorization",
          "Basic #{Base.encode64("admin:secretpw")}"
        )
        |> put_req_header("x-api-key", "valid-api-key")
        |> upstream_auth_headers(bypass)

      assert headers["authorization"] == ["Bearer dest-token"]
      assert headers["x-api-key"] == []
    end

    test "strips proxy-authorization", %{bypass: bypass, channel: channel} do
      headers =
        conn(:get, "/channels/#{channel.id}/test")
        |> put_req_header(
          "proxy-authorization",
          "Basic #{Base.encode64("proxy:pw")}"
        )
        |> upstream_auth_headers(bypass)

      assert headers["proxy-authorization"] == []
    end

    defp upstream_auth_headers(conn, bypass) do
      test = self()

      Bypass.expect_once(bypass, "GET", "/test", fn upstream ->
        headers =
          Map.new(
            ["authorization", "x-api-key", "proxy-authorization"],
            &{&1, Plug.Conn.get_req_header(upstream, &1)}
          )

        send(test, {:upstream_auth_headers, headers})
        Plug.Conn.send_resp(upstream, 200, "ok")
      end)

      assert %{status: 200} = send_to_endpoint(conn)
      assert_received {:upstream_auth_headers, headers}
      headers
    end
  end

  describe "destination answers" do
    for status <- [400, 404, 422, 500, 503] do
      test "a #{status} from the destination passes through untouched", %{
        conn: conn,
        bypass: bypass,
        channel: channel
      } do
        status = unquote(status)
        body = ~s({"error":"Not Found","detail":"the destination's own"})

        Bypass.expect_once(bypass, "GET", "/thing", fn conn ->
          conn
          |> Plug.Conn.put_resp_header("x-destination", "kept")
          |> Plug.Conn.put_resp_content_type("application/vnd.dest+json")
          |> Plug.Conn.send_resp(status, body)
        end)

        resp =
          conn
          |> put_req_header("accept", "application/problem+json")
          |> get("/channels/#{channel.id}/thing")

        assert resp.status == status
        assert resp.resp_body == body

        assert Plug.Conn.get_resp_header(resp, "content-type") == [
                 "application/vnd.dest+json; charset=utf-8"
               ]

        assert Plug.Conn.get_resp_header(resp, "x-destination") == ["kept"]
        assert Plug.Conn.get_resp_header(resp, "www-authenticate") == []
      end
    end
  end
end
