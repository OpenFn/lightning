defmodule Lightning.OpenTelemetry.FilteringExporterTest do
  use ExUnit.Case, async: true

  require Record

  alias Lightning.OpenTelemetry.FilteringExporter

  Record.defrecordp(
    :span_rec,
    :span,
    Record.extract(:span, from_lib: "opentelemetry/include/otel_span.hrl")
  )

  # No exporter in the SDK declines to start, so this stands in for one that
  # does. Only `init/1` is defined, since nothing calls anything else on an
  # exporter that returned `:ignore`.
  defmodule IgnoringExporter do
    def init(_opts), do: :ignore
  end

  # `otel_exporter_pid`'s `shutdown/1` does nothing observable, so it cannot
  # show that the call was passed on. This one tells the test it was called,
  # and with which state.
  defmodule ShutdownNotifyingExporter do
    def init(pid), do: {:ok, pid}

    def shutdown(pid) do
      send(pid, {:shutdown, pid})
      :ok
    end
  end

  describe "behaviour" do
    test "implements :otel_exporter_traces" do
      assert :otel_exporter_traces in (Keyword.get_values(
                                         FilteringExporter.module_info(
                                           :attributes
                                         ),
                                         :behaviour
                                       )
                                       |> List.flatten())
    end
  end

  describe "init/1" do
    test "initialises the wrapped exporter and keeps it with its state" do
      assert {:ok, {:otel_exporter_pid, self()}} ==
               FilteringExporter.init(%{exporter: {:otel_exporter_pid, self()}})
    end

    test "passes on a wrapped exporter's :ignore" do
      assert :ignore ==
               FilteringExporter.init(%{exporter: {IgnoringExporter, %{}}})
    end
  end

  describe "export/3" do
    test "hands every span in the table to the wrapped exporter" do
      {:ok, state} =
        FilteringExporter.init(%{exporter: {:otel_exporter_pid, self()}})

      tab = span_table()

      :ets.insert(
        tab,
        span_rec(
          name: :first,
          attributes: :otel_attributes.new(%{}, 128, :infinity)
        )
      )

      :ets.insert(
        tab,
        span_rec(
          name: :second,
          attributes: :otel_attributes.new(%{}, 128, :infinity)
        )
      )

      assert :ok ==
               FilteringExporter.export(tab, :otel_resource.create([]), state)

      assert_received {:span, span_rec(name: :first)}
      assert_received {:span, span_rec(name: :second)}
    end

    test "hands the wrapped exporter scrubbed spans" do
      {:ok, state} =
        FilteringExporter.init(%{exporter: {:otel_exporter_pid, self()}})

      tab = span_table()

      :ets.insert(
        tab,
        span_rec(
          name: :redactible,
          attributes:
            :otel_attributes.new(%{"url.path": "/i/abc123"}, 128, :infinity)
        )
      )

      :ets.insert(
        tab,
        span_rec(
          name: :other_redactible,
          attributes:
            :otel_attributes.new(%{"url.path": "/i/def456"}, 128, :infinity)
        )
      )

      assert :ok ==
               FilteringExporter.export(tab, :otel_resource.create([]), state)

      assert_received {:span,
                       span_rec(name: :redactible, attributes: attributes)}

      assert %{"url.path": "[redacted]"} == :otel_attributes.map(attributes)

      assert_received {:span,
                       span_rec(name: :other_redactible, attributes: attributes)}

      assert %{"url.path": "[redacted]"} == :otel_attributes.map(attributes)
    end

    defmodule TableReportingExporter do
      def init(pid), do: {:ok, pid}

      def export(tab, _resource, pid) do
        send(pid, {:exported_table, tab})
        :ok
      end
    end

    test "deletes the table it hands the wrapped exporter" do
      {:ok, state} =
        FilteringExporter.init(%{exporter: {TableReportingExporter, self()}})

      tab = span_table()

      :ets.insert(
        tab,
        span_rec(
          name: :first,
          attributes: :otel_attributes.new(%{}, 128, :infinity)
        )
      )

      FilteringExporter.export(tab, :otel_resource.create([]), state)

      assert_received {:exported_table, exported}
      assert :undefined == :ets.info(exported)
    end
  end

  describe "shutdown/1" do
    test "shuts down the wrapped exporter with its own state" do
      {:ok, state} =
        FilteringExporter.init(%{exporter: {ShutdownNotifyingExporter, self()}})

      assert :ok == FilteringExporter.shutdown(state)

      assert_received {:shutdown, pid} when pid == self()
    end
  end

  describe "scrub/1" do
    test "redacts all redactible attributes present" do
      span =
        span_rec(
          attributes:
            :otel_attributes.new(
              %{
                "url.path": "/i/abc123",
                "url.query": "token=abc123",
                "client.address": "1.1.1.1",
                "network.peer.address": "2.2.2.2",
                "server.address": "3.3.3.3",
                "network.local.address": "4.4.4.4",
                "http.request.method": :GET
              },
              128,
              :infinity
            )
        )

      span_rec(attributes: attributes) = FilteringExporter.scrub(span)

      assert %{
               "url.path": "[redacted]",
               "url.query": "[redacted]",
               "client.address": "[redacted]",
               "network.peer.address": "[redacted]",
               "server.address": "[redacted]",
               "network.local.address": "[redacted]",
               "http.request.method": :GET
             } == :otel_attributes.map(attributes)
    end

    test "does not touch the span if there are no redactible attributes" do
      span =
        span_rec(
          attributes:
            :otel_attributes.new(
              %{
                "http.request.method": :GET,
                "http.response.status_code": 200
              },
              10,
              64
            )
        )

      assert span == FilteringExporter.scrub(span)
    end
  end

  # Built the way the batch processor builds the table it hands an exporter
  # (`otel_batch_processor:new_export_table/1`): a duplicate bag keyed on the
  # instrumentation scope, which the OTLP exporter relies on to group spans.
  # Record indexes are zero-based with the tag at 0; ETS positions are
  # one-based.
  defp span_table do
    :ets.new(:spans, [
      :duplicate_bag,
      {:keypos, span_rec(:instrumentation_scope) + 1}
    ])
  end
end
