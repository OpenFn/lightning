defmodule Lightning.OpenTelemetry.RedactingProcessor do
  @moduledoc """
  A redacting processor for OpenTelemetry spans.

  Redacts potentially sensitive information from span
  attributes, before they are exported.
  """

  @behaviour :otel_span_processor

  require Record

  Record.defrecordp(
    :span,
    :span,
    Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl")
  )

  # Every attribute that can hold an address, rather than only the ones that
  # hold a *caller's* address:
  #
  #   * `client.address` is the caller as forwarded by any proxy in front of
  #     us, and `network.peer.address` is whatever opened the socket. Either
  #     can be a person's IP, and cowboy sets both when a request span starts.
  #   * `server.address` is our own address, but it is read from the
  #     `host`/`x-forwarded-host` header, which the caller supplies and which
  #     is an IP literal whenever a client addresses the instance by IP. The
  #     instance is already named by `service.name` in the OTLP resource, so
  #     the attribute is not carrying information we lose. `server.port`
  #     survives: a port is not an address.
  #   * `network.local.address` is ours as well. It is an opt-in attribute we
  #     do not currently enable, and is listed because redaction only touches
  #     keys that are present - covering it now costs nothing and means
  #     switching the opt-in attributes on later cannot quietly start
  #     exporting addresses.
  @redactions [
    :"url.path",
    :"url.query",
    :"client.address",
    :"network.peer.address",
    :"server.address",
    :"network.local.address"
  ]

  def on_start(_ctx, span(attributes: attrs) = s, _config) do
    attrs_map = :otel_attributes.map(attrs)

    updated_attrs =
      case Enum.filter(@redactions, &Map.has_key?(attrs_map, &1)) do
        [] -> attrs
        keys -> :otel_attributes.set(Map.new(keys, &{&1, "[redacted]"}), attrs)
      end

    span(s, attributes: updated_attrs)
  end

  def on_end(_span, _config), do: true

  def force_flush(_config), do: :ok
end
