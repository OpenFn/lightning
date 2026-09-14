defmodule LightningWeb.SentryScrubberTest do
  use ExUnit.Case, async: true

  import Plug.Test

  alias LightningWeb.SentryScrubber

  defp with_headers(headers) do
    Enum.reduce(headers, conn(:post, "/i/some-webhook"), fn {name, value}, acc ->
      Plug.Conn.put_req_header(acc, name, value)
    end)
  end

  describe "scrub_headers/1" do
    test "drops the headers Sentry redacts by default" do
      headers =
        with_headers([
          {"authorization", "Basic dXNlcjpwYXNz"},
          {"cookie", "session=abc"},
          {"user-agent", "acme-integration/1.2"}
        ])
        |> SentryScrubber.scrub_headers()

      refute Map.has_key?(headers, "authorization")
      refute Map.has_key?(headers, "cookie")
      assert headers["user-agent"] == "acme-integration/1.2"
    end

    test "drops x-api-key, which Sentry's defaults miss" do
      headers =
        with_headers([
          {"x-api-key", "sup3r-s3cret-api-key"},
          {"content-type", "application/json"}
        ])
        |> SentryScrubber.scrub_headers()

      refute Map.has_key?(headers, "x-api-key"),
             "x-api-key is one of the two headers webhook auth reads, so an " <>
               "error on /i/* shipped the shared secret to Sentry"

      assert headers["content-type"] == "application/json"
    end

    test "drops proxy-authorization" do
      headers =
        with_headers([{"proxy-authorization", "Basic cHJveHk6c2VjcmV0"}])
        |> SentryScrubber.scrub_headers()

      refute Map.has_key?(headers, "proxy-authorization")
    end
  end

  describe "the wiring in LightningWeb.Endpoint" do
    # Guards the option shape, not the scrubbing. If `:header_scrubber` were
    # misnamed or the `{module, function}` form unsupported, the SDK would
    # quietly fall back to its own defaults and this fix would be inert.
    test "PlugContext accepts the endpoint's option and applies the scrubber" do
      opts =
        Sentry.PlugContext.init(
          header_scrubber: {SentryScrubber, :scrub_headers}
        )

      conn(:post, "/i/some-webhook")
      |> Plug.Conn.put_req_header("x-api-key", "sup3r-s3cret-api-key")
      |> Plug.Conn.put_req_header("user-agent", "acme-integration/1.2")
      |> Sentry.PlugContext.call(opts)

      %{request: request} = Sentry.Context.get_all()

      refute Map.has_key?(request.headers, "x-api-key")
      assert request.headers["user-agent"] == "acme-integration/1.2"
    end

    # `Sentry.PlugCapture` scrubs `Plug.Conn` structs carried in an exception's
    # args through `Sentry.Scrubber.scrub/1`, which honours whatever PlugContext
    # registered for the request. The header scrubber has to hold on that route
    # too, not just on the request context.
    test "a conn carried by an exception is scrubbed through the same scrubber" do
      opts =
        Sentry.PlugContext.init(
          header_scrubber: {SentryScrubber, :scrub_headers}
        )

      conn =
        conn(:post, "/i/some-webhook")
        |> Plug.Conn.put_req_header("x-api-key", "sup3r-s3cret-api-key")

      Sentry.PlugContext.call(conn, opts)

      assert Sentry.Scrubber.scrub(conn).req_headers == []
    end
  end
end
