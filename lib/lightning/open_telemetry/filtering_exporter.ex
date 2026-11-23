defmodule Lightning.OpenTelemetry.FilteringExporter do
  @moduledoc """
  Wraps a traces exporter. For now it hands every batch on unchanged; span
  filtering is added in later commits.
  """

  @behaviour :otel_exporter_traces

  require Record

  Record.defrecordp(
    :span,
    :span,
    Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl")
  )

  @redactions [
    :"url.path"
  ]

  @impl true
  def init(%{exporter: {mod, opts}}) do
    case mod.init(opts) do
      {:ok, state} -> {:ok, {mod, state}}
      :ignore -> :ignore
    end
  end

  def scrub(span(attributes: attrs) = s) do
    attrs_map = :otel_attributes.map(attrs)

    updated_attrs =
      case @redactions |> Enum.filter(&Map.has_key?(attrs_map, &1)) do
        [] -> attrs
        keys -> :otel_attributes.set(Map.new(keys, &{&1, "[redacted]"}), attrs)
      end

    span(s, attributes: updated_attrs)
  end

  @impl true
  def export(tab, resource, {mod, state}), do: mod.export(tab, resource, state)

  @impl true
  def shutdown({mod, state}), do: mod.shutdown(state)

  def allowed_attributes do
    []
  end
end
