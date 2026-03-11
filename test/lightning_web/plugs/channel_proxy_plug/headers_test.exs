defmodule LightningWeb.ChannelProxyPlug.HeadersTest do
  use ExUnit.Case, async: true

  alias LightningWeb.ChannelProxyPlug.Headers
  alias LightningWeb.ChannelProxyPlug.SinkRequest

  import Plug.Test, only: [conn: 2]

  describe "reject_header/2" do
    test "removes matching header case-insensitively" do
      headers = [{"Content-Type", "text/html"}, {"X-Custom", "val"}]

      assert Headers.reject_header(headers, "content-type") == [
               {"X-Custom", "val"}
             ]
    end

    test "returns headers unchanged when name not found" do
      headers = [{"Content-Type", "text/html"}]
      assert Headers.reject_header(headers, "x-missing") == headers
    end
  end

  describe "set_header/3" do
    test "sets a new header value" do
      headers = [{"accept", "text/html"}]
      result = Headers.set_header(headers, "authorization", "Bearer tok")
      assert {"authorization", "Bearer tok"} in result
    end

    test "replaces existing header" do
      headers = [{"authorization", "old"}]
      result = Headers.set_header(headers, "authorization", "new")
      assert result == [{"authorization", "new"}]
    end

    test "nil value is a no-op" do
      headers = [{"accept", "text/html"}]
      assert Headers.set_header(headers, "authorization", nil) == headers
    end
  end

  describe "add_proxy_headers/2" do
    test "adds x-forwarded-for, x-forwarded-host, and x-forwarded-proto" do
      c = conn(:get, "/test") |> put_req_header("host", "example.com")
      result = Headers.add_proxy_headers([], c)

      assert {"x-forwarded-host", "example.com"} in result
      assert {"x-forwarded-proto", "http"} in result
      assert Enum.any?(result, fn {k, _} -> k == "x-forwarded-for" end)
    end

    test "appends to existing x-forwarded-for" do
      c = conn(:get, "/test") |> put_req_header("x-forwarded-for", "1.2.3.4")
      result = Headers.add_proxy_headers([], c)

      {_, xff} = Enum.find(result, fn {k, _} -> k == "x-forwarded-for" end)
      assert xff =~ "1.2.3.4, "
    end
  end

  describe "build_outbound_headers/2" do
    test "strips original x-request-id header and sets new one from SinkRequest" do
      c = conn(:get, "/test") |> put_req_header("x-request-id", "original-id")

      req = %SinkRequest{
        channel: nil,
        snapshot: nil,
        request_id: "new-request-id",
        forward_path: "/",
        client_identity: "127.0.0.1",
        auth_header: nil
      }

      result = Headers.build_outbound_headers(c, req)

      x_request_ids = for {"x-request-id", v} <- result, do: v
      assert x_request_ids == ["new-request-id"]
    end

    test "sets authorization header from SinkRequest" do
      c = conn(:get, "/test")

      req = %SinkRequest{
        channel: nil,
        snapshot: nil,
        request_id: "req-1",
        forward_path: "/",
        client_identity: "127.0.0.1",
        auth_header: "Bearer secret"
      }

      result = Headers.build_outbound_headers(c, req)

      assert {"authorization", "Bearer secret"} in result
    end

    test "no authorization header when auth_header is nil" do
      c = conn(:get, "/test")

      req = %SinkRequest{
        channel: nil,
        snapshot: nil,
        request_id: "req-1",
        forward_path: "/",
        client_identity: "127.0.0.1",
        auth_header: nil
      }

      result = Headers.build_outbound_headers(c, req)

      refute Enum.any?(result, fn {k, _} -> k == "authorization" end)
    end
  end

  defp put_req_header(%Plug.Conn{} = conn, key, value) do
    %{conn | req_headers: [{key, value} | conn.req_headers]}
  end
end
