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

  alias OpenTelemetry.SemConv

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
      :"db.instance",
      # SemConv replaces name wth namespace, but Ecto does not emit namespace
      :"db.name",
      SemConv.Incubating.DBAttributes.db_system(),
      :"db.type",
      :decode_time_microseconds,
      SemConv.ErrorAttributes.error_type(),
      SemConv.HTTPAttributes.http_request_method(),
      SemConv.HTTPAttributes.http_response_status_code(),
      SemConv.HTTPAttributes.http_route(),
      :idle_time_microseconds,
      SemConv.Incubating.MessagingAttributes.messaging_client_id(),
      SemConv.Incubating.MessagingAttributes.messaging_destination_name(),
      SemConv.Incubating.MessagingAttributes.messaging_message_id(),
      SemConv.Incubating.MessagingAttributes.messaging_operation_name(),
      SemConv.Incubating.MessagingAttributes.messaging_operation_type(),
      SemConv.Incubating.MessagingAttributes.messaging_system(),
      SemConv.NetworkAttributes.network_protocol_name(),
      SemConv.NetworkAttributes.network_protocol_version(),
      :"oban.job.attempt",
      :"oban.job.inserted_at",
      :"oban.job.job_id",
      :"oban.job.max_attempts",
      :"oban.job.priority",
      :"oban.job.scheduled_at",
      :"oban.job.worker",
      :"phoenix.action",
      :"phoenix.plug",
      :query_time_microseconds,
      :queue_time_microseconds,
      SemConv.ServerAttributes.server_port(),
      :source,
      :total_time_microseconds,
      SemConv.URLAttributes.url_scheme()
    ]
  end
end
