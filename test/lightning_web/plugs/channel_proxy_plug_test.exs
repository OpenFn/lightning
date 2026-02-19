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
        sink_url: "http://localhost:#{bypass.port}",
        enabled: true
      )

    disabled_channel =
      insert(:channel,
        project: project,
        sink_url: "http://localhost:#{bypass.port}",
        enabled: false
      )

    {:ok, bypass: bypass, channel: channel, disabled_channel: disabled_channel}
  end

  describe "proxying requests" do
    test "GET proxied to sink with correct path", %{
      conn: conn,
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "GET", "/test", fn conn ->
        Plug.Conn.send_resp(conn, 200, "ok from sink")
      end)

      resp = get(conn, "/channels/#{channel.id}/test")

      assert resp.status == 200
      assert resp.resp_body == "ok from sink"
    end

    test "POST with body arrives at sink unchanged", %{
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

    test "proxy headers forwarded to sink", %{
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

    test "response headers from sink forwarded to client", %{
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

    test "sink timeout returns 502", %{
      conn: conn,
      channel: channel
    } do
      # Channel's sink_url points to a port with nothing running
      port = Enum.random(59_000..59_999)

      channel
      |> Ecto.Changeset.change(sink_url: "http://localhost:#{port}")
      |> Lightning.Repo.update!()

      resp = get(conn, "/channels/#{channel.id}/test")

      assert resp.status in [502, 504]
    end
  end

  describe "handler persistence" do
    setup do
      on_exit(fn ->
        Lightning.Channels.TaskSupervisor
        |> Task.Supervisor.children()
        |> Enum.each(fn pid ->
          ref = Process.monitor(pid)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          after
            5_000 -> :ok
          end
        end)
      end)
    end

    test "creates ChannelRequest and ChannelEvent on successful proxy", %{
      conn: conn,
      bypass: bypass,
      channel: channel
    } do
      Lightning.subscribe("channels:#{channel.id}")

      Bypass.expect_once(bypass, "GET", "/persisted", fn conn ->
        Plug.Conn.send_resp(conn, 200, "persisted response")
      end)

      resp = get(conn, "/channels/#{channel.id}/persisted")
      assert resp.status == 200

      assert_receive {:channel_request_completed, request_id}, 1000

      request = Lightning.Repo.get!(ChannelRequest, request_id)
      assert request.state == :success
      assert request.completed_at != nil

      event =
        Lightning.Repo.one!(
          from(e in ChannelEvent, where: e.channel_request_id == ^request.id)
        )

      assert event.type == :sink_response
      assert event.response_status == 200
      assert event.latency_ms != nil
      assert event.request_method == "GET"
      assert event.request_path == "/persisted"
    end

    test "creates error-state request on connection failure", %{
      conn: conn,
      channel: channel
    } do
      Lightning.subscribe("channels:#{channel.id}")

      port = Enum.random(59_000..59_999)

      channel
      |> Ecto.Changeset.change(sink_url: "http://localhost:#{port}")
      |> Lightning.Repo.update!()

      resp = get(conn, "/channels/#{channel.id}/fail")
      assert resp.status in [502, 504]

      assert_receive {:channel_request_completed, request_id}, 1000

      request = Lightning.Repo.get!(ChannelRequest, request_id)
      assert request.state in [:error, :timeout]
      assert request.completed_at != nil
    end
  end

  describe "source authentication" do
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
      project = insert(:project)

      channel =
        insert(:channel,
          project: project,
          sink_url: "http://localhost:#{bypass.port}",
          enabled: true,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :source,
              webhook_auth_method:
                build(:webhook_auth_method,
                  project: project,
                  auth_type: :api,
                  api_key: "valid-api-key"
                )
            )
          ]
        )

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

    test "API key auth — wrong key returns 404", %{bypass: bypass} do
      project = insert(:project)

      channel =
        insert(:channel,
          project: project,
          sink_url: "http://localhost:#{bypass.port}",
          enabled: true,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :source,
              webhook_auth_method:
                build(:webhook_auth_method,
                  project: project,
                  auth_type: :api,
                  api_key: "correct-key"
                )
            )
          ]
        )

      resp =
        conn(:get, "/channels/#{channel.id}/protected")
        |> put_req_header("x-api-key", "wrong-key")
        |> send_to_endpoint()

      assert resp.status == 404
      assert %{"error" => "Not Found"} = json_response(resp, 404)
    end

    test "API key auth — no key sent returns 401", %{bypass: bypass} do
      project = insert(:project)

      channel =
        insert(:channel,
          project: project,
          sink_url: "http://localhost:#{bypass.port}",
          enabled: true,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :source,
              webhook_auth_method:
                build(:webhook_auth_method,
                  project: project,
                  auth_type: :api,
                  api_key: "some-key"
                )
            )
          ]
        )

      resp =
        conn(:get, "/channels/#{channel.id}/protected")
        |> send_to_endpoint()

      assert resp.status == 401
      assert %{"error" => "Unauthorized"} = json_response(resp, 401)
    end

    test "Basic auth — correct credentials allows request", %{bypass: bypass} do
      project = insert(:project)

      channel =
        insert(:channel,
          project: project,
          sink_url: "http://localhost:#{bypass.port}",
          enabled: true,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :source,
              webhook_auth_method:
                build(:webhook_auth_method,
                  project: project,
                  auth_type: :basic,
                  username: "admin",
                  password: "secret"
                )
            )
          ]
        )

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

    test "Basic auth — wrong credentials returns 404", %{bypass: bypass} do
      project = insert(:project)

      channel =
        insert(:channel,
          project: project,
          sink_url: "http://localhost:#{bypass.port}",
          enabled: true,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :source,
              webhook_auth_method:
                build(:webhook_auth_method,
                  project: project,
                  auth_type: :basic,
                  username: "admin",
                  password: "secret"
                )
            )
          ]
        )

      encoded = Base.encode64("admin:wrong")

      resp =
        conn(:get, "/channels/#{channel.id}/basic")
        |> put_req_header("authorization", "Basic #{encoded}")
        |> send_to_endpoint()

      assert resp.status == 404
      assert %{"error" => "Not Found"} = json_response(resp, 404)
    end

    test "Basic auth — no auth header returns 401", %{bypass: bypass} do
      project = insert(:project)

      channel =
        insert(:channel,
          project: project,
          sink_url: "http://localhost:#{bypass.port}",
          enabled: true,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :source,
              webhook_auth_method:
                build(:webhook_auth_method,
                  project: project,
                  auth_type: :basic,
                  username: "admin",
                  password: "secret"
                )
            )
          ]
        )

      resp =
        conn(:get, "/channels/#{channel.id}/basic")
        |> send_to_endpoint()

      assert resp.status == 401
      assert %{"error" => "Unauthorized"} = json_response(resp, 401)
    end

    test "multiple auth methods — either matches allows request", %{
      bypass: bypass
    } do
      project = insert(:project)

      channel =
        insert(:channel,
          project: project,
          sink_url: "http://localhost:#{bypass.port}",
          enabled: true,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :source,
              webhook_auth_method:
                build(:webhook_auth_method,
                  project: project,
                  auth_type: :api,
                  api_key: "key-one"
                )
            ),
            build(:channel_auth_method,
              role: :source,
              webhook_auth_method:
                build(:webhook_auth_method,
                  project: project,
                  auth_type: :api,
                  api_key: "key-two"
                )
            )
          ]
        )

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
      project = insert(:project)

      channel =
        insert(:channel,
          project: project,
          sink_url: "http://localhost:#{bypass.port}",
          enabled: true,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :source,
              webhook_auth_method:
                build(:webhook_auth_method,
                  project: project,
                  auth_type: :api,
                  api_key: "mixed-key"
                )
            ),
            build(:channel_auth_method,
              role: :source,
              webhook_auth_method:
                build(:webhook_auth_method,
                  project: project,
                  auth_type: :basic,
                  username: "user",
                  password: "pass"
                )
            )
          ]
        )

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

  describe "sink authentication" do
    setup do
      on_exit(fn ->
        Lightning.Channels.TaskSupervisor
        |> Task.Supervisor.children()
        |> Enum.each(fn pid ->
          ref = Process.monitor(pid)

          receive do
            {:DOWN, ^ref, _, _, _} -> :ok
          after
            5_000 -> :ok
          end
        end)
      end)
    end

    defp create_sink_auth_channel(bypass, schema, body) do
      project = insert(:project)
      user = insert(:user)

      credential =
        insert(:credential, schema: schema, name: "sink-cred", user: user)
        |> with_body(%{body: body})

      project_credential =
        insert(:project_credential,
          project: project,
          credential: credential
        )

      insert(:channel,
        project: project,
        sink_url: "http://localhost:#{bypass.port}",
        enabled: true,
        channel_auth_methods: [
          build(:channel_auth_method,
            role: :sink,
            webhook_auth_method: nil,
            project_credential: project_credential
          )
        ]
      )
    end

    test "Bearer token sent to upstream when channel has http credential with access_token",
         %{bypass: bypass} do
      channel =
        create_sink_auth_channel(bypass, "http", %{
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
        create_sink_auth_channel(bypass, "http", %{
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
        create_sink_auth_channel(bypass, "dhis2", %{
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

    test "no authorization header when channel has no sink auth methods",
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
        create_sink_auth_channel(bypass, "http", %{
          "access_token" => "secret-token"
        })

      Lightning.subscribe("channels:#{channel.id}")

      Bypass.expect_once(bypass, "GET", "/redact-test", fn conn ->
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      resp =
        conn(:get, "/channels/#{channel.id}/redact-test")
        |> send_to_endpoint()

      assert resp.status == 200

      assert_receive {:channel_request_completed, request_id}, 1000

      event =
        Lightning.Repo.one!(
          from(e in ChannelEvent, where: e.channel_request_id == ^request_id)
        )

      # The handler redacts authorization headers before persisting
      # request_headers is stored as a JSON string
      headers = Jason.decode!(event.request_headers)

      auth_header =
        Enum.find(headers, fn [k, _v] -> k == "authorization" end)

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
          sink_url: "http://localhost:#{bypass.port}",
          enabled: true,
          channel_auth_methods: [
            build(:channel_auth_method,
              role: :sink,
              webhook_auth_method: nil,
              project_credential: project_credential
            )
          ]
        )

      Lightning.subscribe("channels:#{channel.id}")

      resp =
        conn(:get, "/channels/#{channel.id}/test")
        |> send_to_endpoint()

      assert resp.status == 502
      assert %{"error" => "Bad Gateway"} = json_response(resp, 502)

      assert_receive {:channel_request_completed, request_id}, 1000

      request = Lightning.Repo.get!(ChannelRequest, request_id)
      assert request.state == :error

      event =
        Lightning.Repo.one!(
          from(e in ChannelEvent, where: e.channel_request_id == ^request_id)
        )

      assert event.error_message == "credential_environment_not_found"
    end

    test "credential with missing auth fields returns 502 with observable error",
         %{bypass: bypass} do
      channel =
        create_sink_auth_channel(bypass, "http", %{
          "baseUrl" => "https://example.com"
        })

      Lightning.subscribe("channels:#{channel.id}")

      resp =
        conn(:get, "/channels/#{channel.id}/test")
        |> send_to_endpoint()

      assert resp.status == 502
      assert %{"error" => "Bad Gateway"} = json_response(resp, 502)

      assert_receive {:channel_request_completed, request_id}, 1000

      request = Lightning.Repo.get!(ChannelRequest, request_id)
      assert request.state == :error

      event =
        Lightning.Repo.one!(
          from(e in ChannelEvent, where: e.channel_request_id == ^request_id)
        )

      assert event.error_message == "credential_missing_auth_fields"
    end

    test "proxy headers (x-forwarded-*) still forwarded alongside auth header",
         %{bypass: bypass} do
      channel =
        create_sink_auth_channel(bypass, "http", %{
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

  defp send_to_endpoint(conn) do
    LightningWeb.Endpoint.call(conn, LightningWeb.Endpoint.init([]))
  end
end
