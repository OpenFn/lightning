defmodule Lightning.OpenTelemetry.FilteringExporter do
  @moduledoc """
  Wraps a traces exporter and redacts sensitive attributes from each span
  before handing the batch on.

  Installed as the SDK's `traces_exporter` by `Lightning.Config.Bootstrap`,
  wrapping the OTLP exporter.
  """

  @behaviour :otel_exporter_traces

  require Logger
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

    scrubbed_spans =
      tab
      |> :ets.tab2list()
      |> tap(&warn_of_dropped_attributes/1)
      |> Enum.map(&scrub/1)

    :ets.insert(scrubbed, scrubbed_spans)

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

  defp warn_of_dropped_attributes(spans) do
    spans
    |> Enum.filter(&has_dropped_attributes/1)
    |> Enum.map(&span(&1, :name))
    |> case do
      [] ->
        :ok

      dropped ->
        names =
          dropped
          |> Enum.uniq()
          |> Enum.sort()

        Logger.warning(
          "Spans with dropped attributes detected: #{inspect(names)}."
        )
    end
  end

  defp has_dropped_attributes(span(attributes: attrs)) do
    :otel_attributes.dropped(attrs) > 0
  end

  def scrub(span(attributes: attrs, status: status) = s) do
    attrs_map = :otel_attributes.map(attrs)

    allowed_attrs =
      attrs_map
      |> Map.take(allowed_attributes())

    span(s,
      attributes:
        :otel_attributes.new(allowed_attrs, map_size(allowed_attrs), :infinity),
      links: :otel_links.new([], 0, 0, :infinity),
      status: scrub_status(status)
    )
  end

  defp scrub_status({:status, code, _message}) do
    {:status, code, ""}
  end

  defp scrub_status(:undefined), do: :undefined

  defp scrub_status(_anything_else) do
    :opentelemetry.status(:error, "Lightning scrubbed unexpected status")
  end

  @impl true
  def shutdown({mod, state}), do: mod.shutdown(state)

  def allowed_attributes do
    [
      :"error.type",
      :"http.request.method",
      :"http.response.status_code",
      :"http.route",
      :"server.port",
      :"url.scheme"
    ]
  end
end
