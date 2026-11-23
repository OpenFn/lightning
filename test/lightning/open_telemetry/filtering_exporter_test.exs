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
      :ets.insert(tab, [span_rec(name: :first), span_rec(name: :second)])

      assert :ok ==
               FilteringExporter.export(tab, :otel_resource.create([]), state)

      assert_received {:span, span_rec(name: :first)}
      assert_received {:span, span_rec(name: :second)}
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
    test "redacts url.path" do
      span =
        span_rec(
          attributes:
            :otel_attributes.new(%{"url.path": "/i/abc123"}, 128, :infinity)
        )

      span_rec(attributes: attributes) = FilteringExporter.scrub(span)

      assert %{"url.path": "[redacted]"} == :otel_attributes.map(attributes)
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
