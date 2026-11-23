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
    :"url.path",
    :"url.query",
    :"client.address",
    :"network.peer.address",
    :"server.address",
    :"network.local.address"
  ]

  @impl true
  def init(%{exporter: {mod, opts}}) do
    case mod.init(opts) do
      {:ok, state} -> {:ok, {mod, state}}
      :ignore -> :ignore
    end
  end

  @impl true
  def export(tab, resource, {mod, state}) do
    scrubbed =
      :ets.new(:scrubbed_spans, [
        :duplicate_bag,
        {:keypos, span(:instrumentation_scope) + 1}
      ])

    :ets.insert(scrubbed, tab |> :ets.tab2list() |> Enum.map(&scrub/1))

    export_result = mod.export(scrubbed, resource, state)

    :ets.delete(scrubbed)

    export_result
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
  def shutdown({mod, state}), do: mod.shutdown(state)

  def allowed_attributes do
    []
  end
end
