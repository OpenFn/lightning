defmodule LightningWeb.ChannelProxyPlugTest do
  use LightningWeb.ConnCase, async: true

  alias Lightning.Channels.{ChannelRequest, ChannelEvent}

  import Ecto.Query
  import Lightning.Factories
  import Plug.Test, only: [conn: 3]

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
        request_id = Plug.Conn.get_req_header(conn, "x-request-id")
        xff = Plug.Conn.get_req_header(conn, "x-forwarded-for")
        xfh = Plug.Conn.get_req_header(conn, "x-forwarded-host")
        xfp = Plug.Conn.get_req_header(conn, "x-forwarded-proto")

        assert request_id != []
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
    end

    test "non-existent channel returns 404", %{conn: conn} do
      resp = get(conn, "/channels/#{Ecto.UUID.generate()}/test")

      assert resp.status == 404
    end

    test "invalid UUID returns 404", %{conn: conn} do
      resp = get(conn, "/channels/not-a-uuid/test")

      assert resp.status == 404
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

  defp send_to_endpoint(conn) do
    LightningWeb.Endpoint.call(conn, LightningWeb.Endpoint.init([]))
  end
end
