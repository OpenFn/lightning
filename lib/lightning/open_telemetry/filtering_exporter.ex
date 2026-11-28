defmodule Lightning.OpenTelemetry.FilteringExporter do
  @moduledoc """
  Wraps a traces exporter and scrubs each span before passing the batch on.
  It's the last point at which span data can be filtered before it leaves the
  application.

  For each span:

    * Attributes not on the allowlist are removed.
    * Attributes that are on the allowlist but with a value that has the wrong
      type are removed. At the time of writing the only example of this is the
      :phoenix.action attribute which is only allowed if the value is an atom.
    * The status message is cleared and the status code kept, where relevant.
    * Links are removed.

  This module does not handle events. The SDK is configured to record none.

  If the SDK has already dropped attributes from a span because of its
  attribute count limit, a warning is logged once per batch. An allowlisted
  attribute may have been among those dropped.

  Setting `OTEL_TRACES_EXPORTER` or `OTEL_SPAN_EVENT_COUNT_LIMIT` would
  bypass this filtering, so Lightning refuses to boot with tracing enabled if
  either is set (see Lightning.Config.Bootstrap).
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

  # A map listing the allowed atributes and the value type that is permitted.
  # Value types are either :anything or :atom.
  @allowed_attributes %{
    :"db.instance" => :anything,
    # SemConv replaces name wth namespace, but Ecto does not emit namespace
    :"db.name" => :anything,
    SemConv.Incubating.DBAttributes.db_system() => :anything,
    :"db.type" => :anything,
    :decode_time_microseconds => :anything,
    SemConv.ErrorAttributes.error_type() => :anything,
    SemConv.HTTPAttributes.http_request_method() => :anything,
    SemConv.HTTPAttributes.http_response_status_code() => :anything,
    SemConv.HTTPAttributes.http_route() => :anything,
    :idle_time_microseconds => :anything,
    SemConv.Incubating.MessagingAttributes.messaging_client_id() => :anything,
    SemConv.Incubating.MessagingAttributes.messaging_destination_name() =>
      :anything,
    SemConv.Incubating.MessagingAttributes.messaging_message_id() => :anything,
    SemConv.Incubating.MessagingAttributes.messaging_operation_name() =>
      :anything,
    SemConv.Incubating.MessagingAttributes.messaging_operation_type() =>
      :anything,
    SemConv.Incubating.MessagingAttributes.messaging_system() => :anything,
    SemConv.NetworkAttributes.network_protocol_name() => :anything,
    SemConv.NetworkAttributes.network_protocol_version() => :anything,
    :"oban.job.attempt" => :anything,
    :"oban.job.inserted_at" => :anything,
    :"oban.job.job_id" => :anything,
    :"oban.job.max_attempts" => :anything,
    :"oban.job.priority" => :anything,
    :"oban.job.scheduled_at" => :anything,
    :"oban.job.worker" => :anything,
    :"phoenix.action" => :atom,
    :"phoenix.plug" => :anything,
    :query_time_microseconds => :anything,
    :queue_time_microseconds => :anything,
    SemConv.ServerAttributes.server_port() => :anything,
    :source => :anything,
    :total_time_microseconds => :anything,
    SemConv.URLAttributes.url_scheme() => :anything
  }

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
      |> Map.filter(fn {k, v} ->
        case @allowed_attributes[k] do
          nil -> false
          :anything -> true
          :atom -> is_atom(v)
        end
      end)

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

  def allowed_attributes, do: @allowed_attributes
end
