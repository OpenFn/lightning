defmodule Lightning.OpenTelemetry.FilteringExporter do
  @moduledoc """
  Wraps a traces exporter and redacts sensitive attributes from each span
  before handing the batch on.

  Installed as the SDK's `traces_exporter` by `Lightning.Config.Bootstrap`,
  wrapping the OTLP exporter.
  """

  @behaviour :otel_exporter_traces

  require Record

  Record.defrecordp(
    :span,
    :span,
    Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl")
  )

  @impl true
  def init(%{exporter: {mod, opts}}) do
    case mod.init(opts) do
      {:ok, state} -> {:ok, {mod, state}}
      :ignore -> :ignore
    end
  end

  @impl true
  def export(tab, resource, {mod, state}) do
    [type, keypos] = table_attributes(tab)

    scrubbed = :ets.new(:scrubbed_spans, [type, {:keypos, keypos}])

    :ets.insert(scrubbed, tab |> :ets.tab2list() |> Enum.map(&scrub/1))

    try do
      mod.export(scrubbed, resource, state)
    after
      :ets.delete(scrubbed)
    end
  end

  defp table_attributes(tab) do
    [
      :ets.info(tab, :type),
      :ets.info(tab, :keypos)
    ]
  end

  def scrub(span() = s) do
    span(s, attributes: :otel_attributes.new(%{}, 128, :infinity))
  end

  @impl true
  def shutdown({mod, state}), do: mod.shutdown(state)

  def allowed_attributes do
    []
  end
end
