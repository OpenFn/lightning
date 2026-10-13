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

  @redactions [:"url.path", :"url.query"]

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
