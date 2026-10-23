defmodule LightningWeb.ChannelProxyRefusalsTest do
  use LightningWeb.ConnCase, async: true

  alias Lightning.Channels.{ChannelRequest, ChannelEvent}

  import Ecto.Query
  import Lightning.Factories
  import LightningWeb.API.ProblemHelpers
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

  describe "response security headers" do
    test "set on a proxied response", %{
      conn: conn,
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "GET", "/test", fn conn ->
        Plug.Conn.send_resp(conn, 200, "ok")
      end)

      resp = get(conn, "/channels/#{channel.id}/test")

      assert resp.status == 200
      assert_security_headers(resp)
    end

    test "destination cannot override them", %{
      conn: conn,
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "GET", "/bad", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-security-policy", "default-src *")
        |> Plug.Conn.put_resp_header("x-frame-options", "ALLOWALL")
        |> Plug.Conn.put_resp_header("x-content-type-options", "")
        |> Plug.Conn.put_resp_header("referrer-policy", "unsafe-url")
        |> Plug.Conn.put_resp_content_type("text/html")
        |> Plug.Conn.send_resp(200, "<script>alert(1)</script>")
      end)

      resp = get(conn, "/channels/#{channel.id}/bad")

      assert resp.status == 200
      assert_security_headers(resp)
    end

    test "set-cookie from the destination is not forwarded", %{
      conn: conn,
      bypass: bypass,
      channel: channel
    } do
      Bypass.expect_once(bypass, "GET", "/cookie", fn conn ->
        conn
        |> Plug.Conn.put_resp_header(
          "set-cookie",
          "_lightning_key=forged; Path=/"
        )
        |> Plug.Conn.send_resp(200, "ok")
      end)

      resp = get(conn, "/channels/#{channel.id}/cookie")

      assert resp.status == 200
      assert Plug.Conn.get_resp_header(resp, "set-cookie") == []
    end

    test "set on the unknown-channel response", %{conn: conn} do
      resp = get(conn, "/channels/#{Ecto.UUID.generate()}/test")

      assert resp.status == 404
      assert_security_headers(resp)
    end

    test "set on the unauthorized response", %{conn: conn, bypass: bypass} do
      project = insert(:project)

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
                  api_key: "valid-api-key"
                )
            )
          ]
        )

      resp = get(conn, "/channels/#{channel.id}/test")

      assert resp.status == 401
      assert_security_headers(resp)
    end
  end

  describe "error cases" do
    test "disabled channel returns 404", %{
      conn: conn,
      disabled_channel: disabled_channel
    } do
      resp = get(conn, "/channels/#{disabled_channel.id}/test")

      assert_problem(resp, 404, :not_found, [])
    end

    test "non-existent channel returns 404", %{conn: conn} do
      resp = get(conn, "/channels/#{Ecto.UUID.generate()}/test")

      assert_problem(resp, 404, :not_found, [])
    end

    test "invalid UUID returns 404", %{conn: conn} do
      resp = get(conn, "/channels/not-a-uuid/test")

      assert_problem(resp, 404, :not_found, [])
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

  describe "SSRF egress guard" do
    test "refuses to proxy to the cloud metadata IP (AWS IMDS / GCP metadata)",
         %{conn: conn} do
      project = insert(:project)

      channel =
        insert(:channel,
          project: project,
          destination_url: "http://169.254.169.254/latest/meta-data/",
          enabled: true
        )

      resp = get(conn, "/channels/#{channel.id}/latest/meta-data/")

      assert resp.status == 403
      refute resp.resp_body =~ "169.254.169.254"
    end

    test "refuses to proxy to an RFC1918 private-network address", %{conn: conn} do
      project = insert(:project)

      channel =
        insert(:channel,
          project: project,
          destination_url: "http://10.0.0.1",
          enabled: true
        )

      resp = get(conn, "/channels/#{channel.id}/admin")

      assert resp.status == 403
      refute resp.resp_body =~ "10.0.0.1"
    end

    test "refuses to proxy to a private-range address not on the allow-list", %{
      conn: conn
    } do
      # A second RFC1918 address to lock in the general private-range case:
      # with blocking on (default) and no allow-list entry, the block applies
      # before any socket is opened.
      project = insert(:project)

      channel =
        insert(:channel,
          project: project,
          destination_url: "http://10.0.0.10",
          enabled: true
        )

      resp = get(conn, "/channels/#{channel.id}/admin")

      assert resp.status == 403
      refute resp.resp_body =~ "10.0.0.10"
    end
  end

  describe "non-UTF-8 body handling" do
    # `response_body_preview` and `request_body_preview` are stored as :text
    # (UTF-8 only). When an upstream returns binary content (gzip, image, PDF,
    # ...) the bytes can't be persisted as text. Rather than failing the whole
    # insert, we drop the offending preview to nil and persist everything else
    # — headers, hash, size, timing.

    test "non-UTF-8 response body is dropped from preview; rest of event persisted",
         %{bypass: bypass, channel: channel} do
      # `0x8b` is the second byte of the gzip magic number — exactly the byte
      # Postgres rejected in the dev reproduction. We send it raw so Finch
      # cannot transparently decompress it.
      raw_bytes = <<0x1F, 0x8B, 0x08, 0x00, 0xFF, 0xFE>>

      Bypass.expect_once(bypass, "GET", "/binary", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/octet-stream")
        |> Plug.Conn.send_resp(200, raw_bytes)
      end)

      resp =
        conn(:get, "/channels/#{channel.id}/binary")
        |> send_to_endpoint()

      assert resp.status == 200

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      # The request itself succeeded — only the body preview is unstorable.
      assert request.state == :success
      assert request.completed_at != nil

      event =
        Lightning.Repo.one!(
          from(e in ChannelEvent, where: e.channel_request_id == ^request.id)
        )

      assert event.type == :destination_response
      assert event.request_method == "GET"
      assert event.request_path == "/binary"
      assert event.response_status == 200

      # Body preview dropped because it isn't valid UTF-8.
      assert event.response_body_preview == nil

      # Hash and size are still recorded so the audit log can show that a body
      # was returned, even though the bytes couldn't be persisted as text.
      assert is_binary(event.response_body_hash)
      assert event.response_body_size == byte_size(raw_bytes)

      # Headers and timing persist as usual.
      assert is_list(event.request_headers) and event.request_headers != []
      assert is_list(event.response_headers) and event.response_headers != []
      assert is_integer(event.latency_us) and event.latency_us > 0
    end

    test "non-UTF-8 request body is dropped from preview; rest of event persisted",
         %{bypass: bypass, channel: channel} do
      raw_bytes = <<0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A>>

      Bypass.expect_once(bypass, "POST", "/upload", fn conn ->
        Plug.Conn.send_resp(conn, 201, "ok")
      end)

      resp =
        conn(:post, "/channels/#{channel.id}/upload", raw_bytes)
        |> Plug.Conn.put_req_header("content-type", "application/octet-stream")
        |> Plug.Conn.put_req_header("content-length", "#{byte_size(raw_bytes)}")
        |> send_to_endpoint()

      assert resp.status == 201

      request =
        Lightning.Repo.one!(
          from(r in ChannelRequest, where: r.channel_id == ^channel.id)
        )

      assert request.state == :success

      event =
        Lightning.Repo.one!(
          from(e in ChannelEvent, where: e.channel_request_id == ^request.id)
        )

      assert event.request_method == "POST"
      assert event.request_body_preview == nil
      assert is_binary(event.request_body_hash)
      assert event.request_body_size == byte_size(raw_bytes)
    end

    test "valid UTF-8 body is preserved unchanged",
         %{bypass: bypass, channel: channel} do
      Bypass.expect_once(bypass, "GET", "/json", fn conn ->
        conn
        |> Plug.Conn.put_resp_header("content-type", "application/json")
        |> Plug.Conn.send_resp(200, ~s({"hello":"world"}))
      end)

      resp =
        conn(:get, "/channels/#{channel.id}/json")
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

      assert event.response_body_preview == ~s({"hello":"world"})
    end
  end

  describe "answers Lightning builds itself" do
    test "a channel whose snapshot can't be saved answers 500 internal", %{
      conn: conn,
      channel: channel
    } do
      unsnapshottable!(channel)

      resp = get(conn, "/channels/#{channel.id}/test")

      assert_problem(resp, 500, :internal, [])
      assert_security_headers(resp)
    end
  end
end
