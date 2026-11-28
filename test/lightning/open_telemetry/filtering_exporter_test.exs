defmodule Lightning.OpenTelemetry.FilteringExporterTest do
  use ExUnit.Case, async: true
  import ExUnit.CaptureLog

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
            :otel_attributes.new(
              %{
                "http.request.method": :GET,
                "lightning.invented": "secret",
                "lightning.also_invented": "secret"
              },
              128,
              :infinity
            )
        )
      )

      :ets.insert(
        tab,
        span_rec(
          name: :other_redactible,
          attributes:
            :otel_attributes.new(
              %{
                "http.response.status_code": 200,
                "lightning.invented": "secret",
                "lightning.also_invented": "secret"
              },
              128,
              :infinity
            )
        )
      )

      assert :ok ==
               FilteringExporter.export(tab, :otel_resource.create([]), state)

      assert_received {:span,
                       span_rec(name: :redactible, attributes: attributes)}

      assert %{"http.request.method": :GET} == :otel_attributes.map(attributes)

      assert_received {:span,
                       span_rec(name: :other_redactible, attributes: attributes)}

      assert %{"http.response.status_code": 200} ==
               :otel_attributes.map(attributes)
    end

    defmodule TableReportingExporter do
      def init(pid), do: {:ok, pid}

      def export(tab, _resource, pid) do
        send(pid, {:exported_table, tab})
        send(pid, {:table_type, :ets.info(tab, :type)})
        send(pid, {:table_keypos, :ets.info(tab, :keypos)})
        :ok
      end
    end

    test "creates a table to match the provided table" do
      {:ok, state} =
        FilteringExporter.init(%{exporter: {TableReportingExporter, self()}})

      tab = spurious_span_table()

      input_table_type = :ets.info(tab, :type)
      input_table_keypos = :ets.info(tab, :keypos)

      :ets.insert(
        tab,
        span_rec(
          name: :first,
          attributes: :otel_attributes.new(%{}, 128, :infinity)
        )
      )

      FilteringExporter.export(tab, :otel_resource.create([]), state)

      assert_received({:table_type, temporary_table_type})
      assert input_table_type == temporary_table_type

      assert_received({:table_keypos, temporary_table_keypos})
      assert input_table_keypos == temporary_table_keypos
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

    defmodule RaisingExporter do
      def init(pid), do: {:ok, pid}

      def export(tab, _resource, pid) do
        send(pid, {:exported_table, tab})
        raise "export failed"
      end
    end

    test "deletes the table on error and bubbles error up" do
      {:ok, state} =
        FilteringExporter.init(%{exporter: {RaisingExporter, self()}})

      tab = span_table()

      :ets.insert(
        tab,
        span_rec(
          name: :first,
          attributes: :otel_attributes.new(%{}, 128, :infinity)
        )
      )

      assert_raise RuntimeError, "export failed", fn ->
        FilteringExporter.export(tab, :otel_resource.create([]), state)
      end

      assert_received {:exported_table, exported}
      assert :undefined == :ets.info(exported)
    end

    defmodule UnusualResponseExporter do
      def init(pid), do: {:ok, pid}

      def export(_tab, _resource, _pid) do
        :failed_not_retryable
      end
    end

    test "returns the response of the wrapped exporter" do
      {:ok, state} =
        FilteringExporter.init(%{exporter: {UnusualResponseExporter, self()}})

      tab = span_table()

      :ets.insert(
        tab,
        span_rec(
          name: :first,
          attributes: :otel_attributes.new(%{}, 128, :infinity)
        )
      )

      assert :failed_not_retryable =
               FilteringExporter.export(tab, :otel_resource.create([]), state)
    end

    test "writes any spans with dropped attributes to the log as warnings" do
      {:ok, state} =
        FilteringExporter.init(%{exporter: {UnusualResponseExporter, self()}})

      tab = span_table()

      add_span(tab, :span_a, dropped_attr_count: 0)
      add_span(tab, :span_b, dropped_attr_count: 0)
      add_span(tab, :span_c, dropped_attr_count: 1)
      add_span(tab, :span_d, dropped_attr_count: 2)
      add_span(tab, :span_c, dropped_attr_count: 2)
      add_span(tab, :span_b, dropped_attr_count: 1)
      add_span(tab, :span_a, dropped_attr_count: 0)

      log =
        capture_log(fn ->
          FilteringExporter.export(tab, :otel_resource.create([]), state)
        end)

      assert log =~ "[warning] Spans"
      assert log =~ "[:span_b, :span_c, :span_d]"
    end

    defp add_span(table, span_name, dropped_attr_count: dropped_attr_count) do
      :ets.insert(
        table,
        span_rec(
          name: span_name,
          attributes: attributes_with_drops(dropped_attr_count)
        )
      )
    end

    defp attributes_with_drops(dropped_attr_count) when dropped_attr_count < 3 do
      base_limit = 3
      count_limit = base_limit - dropped_attr_count

      :otel_attributes.new(
        %{"http.request.method": :GET},
        count_limit,
        :infinity
      )
      |> then(&:otel_attributes.set(%{"http.response.status_code": 200}, &1))
      |> then(&:otel_attributes.set(%{"lightning.invented": "secret"}, &1))
    end

    defp attributes_with_drops(_dropped_attr_count) do
      raise "Dropping more than 2 attributes is not supported"
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
    test "if there is a single non-allowed attribute, it is removed" do
      span =
        span_rec(
          attributes:
            :otel_attributes.new(
              %{
                "http.request.method": :GET,
                "http.response.status_code": 200,
                "lightning.invented": "secret"
              },
              128,
              :infinity
            )
        )

      span_rec(attributes: attributes) = FilteringExporter.scrub(span)

      attributes_map = :otel_attributes.map(attributes)

      assert attributes_map == %{
               "http.request.method": :GET,
               "http.response.status_code": 200
             }
    end

    test "if there are multiple non-allowed attributes, they are removed" do
      span =
        span_rec(
          attributes:
            :otel_attributes.new(
              %{
                "http.request.method": :GET,
                "http.response.status_code": 200,
                "lightning.invented": "secret",
                "lightning.also_invented": "secret"
              },
              128,
              :infinity
            )
        )

      span_rec(attributes: attributes) = FilteringExporter.scrub(span)

      attributes_map = :otel_attributes.map(attributes)

      assert attributes_map == %{
               "http.request.method": :GET,
               "http.response.status_code": 200
             }
    end

    test "passes through all attributes if only allowed attributes present" do
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

      span_rec(attributes: attributes) = FilteringExporter.scrub(span)

      attributes_map = :otel_attributes.map(attributes)

      assert attributes_map == %{
               "http.request.method": :GET,
               "http.response.status_code": 200
             }
    end

    test "sets limits that ensure no truncation of allowed attributes" do
      span =
        span_rec(
          attributes:
            :otel_attributes.new(
              %{
                "http.request.method": :GET,
                "http.response.status_code": 200,
                "lightning.invented": "secret",
                "lightning.also_invented": "secret"
              },
              128,
              :infinity
            )
        )

      span_rec(
        attributes:
          {:attributes, count_limit, value_length_limit, _dropped, _map}
      ) =
        FilteringExporter.scrub(span)

      assert count_limit == 2
      assert value_length_limit == :infinity
    end

    test "clears the status message, regardless of code" do
      span =
        span_rec(
          attributes: :otel_attributes.new(%{}, 10, 64),
          status: {:status, :unobtainium, "message"}
        )

      span_rec(status: status) = FilteringExporter.scrub(span)

      assert {:status, :unobtainium, ""} == status
    end

    test "leaves an :undefined status alone" do
      span =
        span_rec(
          attributes: :otel_attributes.new(%{}, 10, 64),
          status: :undefined
        )

      span_rec(status: status) = FilteringExporter.scrub(span)

      assert :undefined == status
    end

    test "replaces an unrecognised status with an error status" do
      span =
        span_rec(
          attributes: :otel_attributes.new(%{}, 10, 64),
          status: {:unexpected, :unobtainium, "secret"}
        )

      span_rec(status: status) = FilteringExporter.scrub(span)

      assert {:status, :error, "Lightning scrubbed unexpected status"} == status
    end

    test "scrubs the links when there is a single link" do
      span =
        span_rec(
          attributes: :otel_attributes.new(%{}, 10, 64),
          links:
            build_links([
              :opentelemetry.link(1, 2, %{}, :otel_tracestate.new())
            ])
        )

      assert span_rec(span, :links) |> :otel_links.list() |> length() == 1

      assert span_rec(links: scrubbed_links) = FilteringExporter.scrub(span)

      assert scrubbed_links |> :otel_links.list() |> length() == 0
    end

    test "scrubs the links when there are multiple links" do
      span =
        span_rec(
          attributes: :otel_attributes.new(%{}, 10, 64),
          links:
            build_links([
              :opentelemetry.link(1, 2, %{}, :otel_tracestate.new()),
              :opentelemetry.link(3, 4, %{}, :otel_tracestate.new())
            ])
        )

      assert span_rec(span, :links) |> :otel_links.list() |> length() == 2

      assert span_rec(links: scrubbed_links) = FilteringExporter.scrub(span)

      assert scrubbed_links |> :otel_links.list() |> length() == 0
    end

    test "leaves links empty when there are no links" do
      span =
        span_rec(
          attributes: :otel_attributes.new(%{}, 10, 64),
          links: build_links([])
        )

      assert span_rec(span, :links) |> :otel_links.list() |> length() == 0

      assert span_rec(links: scrubbed_links) = FilteringExporter.scrub(span)

      assert scrubbed_links |> :otel_links.list() |> length() == 0
    end

    test "correctly scrubs a span with attributes, status and links" do
      span =
        span_rec(
          name: :redactible,
          attributes:
            :otel_attributes.new(
              %{
                "http.response.status_code": 200,
                "lightning.invented": "secret",
                "lightning.also_invented": "secret"
              },
              128,
              :infinity
            ),
          links:
            build_links([
              :opentelemetry.link(1, 2, %{}, :otel_tracestate.new()),
              :opentelemetry.link(3, 4, %{}, :otel_tracestate.new())
            ]),
          status: {:status, :error, "message"}
        )

      assert span_rec(span, :links) |> :otel_links.list() |> length() == 2

      span_rec(attributes: attributes, links: scrubbed_links, status: status) =
        FilteringExporter.scrub(span)

      assert %{"http.response.status_code": 200} ==
               :otel_attributes.map(attributes)

      assert scrubbed_links |> :otel_links.list() |> length() == 0

      assert {:status, :error, ""} == status
    end

    test "removes phoenix.action if the value is not an atom" do
      span =
        span_rec(
          name: :redactible,
          attributes:
            :otel_attributes.new(
              %{
                "http.response.status_code": 200,
                "phoenix.action": "secret"
              },
              128,
              :infinity
            )
        )

      span_rec(attributes: attributes) = FilteringExporter.scrub(span)

      assert %{"http.response.status_code": 200} ==
               :otel_attributes.map(attributes)
    end

    test "does not remove phoenix.action if the value is an atom" do
      span =
        span_rec(
          name: :redactible,
          attributes:
            :otel_attributes.new(
              %{
                "http.response.status_code": 200,
                "phoenix.action": :not_so_secret
              },
              128,
              :infinity
            )
        )

      span_rec(attributes: attributes) = FilteringExporter.scrub(span)

      assert %{
               "http.response.status_code": 200,
               "phoenix.action": :not_so_secret
             } == :otel_attributes.map(attributes)
    end

    defp build_links(links) do
      :otel_links.new(links, length(links), 128, :infinity)
    end
  end

  describe "allowed_attributes/0" do
    # Written out as literal atoms on purpose. Every key on this list leaves
    # the process. Adding one, or a semconv upgrade changing the value of a
    # constant used in the lib, has to show up as a change to this test.

    # Deliberately absent: `user_agent.original` (D2), and Oban's
    # `messaging.batch.message_count`, which only `OpentelemetryOban.insert*`
    # sets and Lightning does not call.
    test "is exactly the reviewed list" do
      assert FilteringExporter.allowed_attributes() == %{
               # Ecto, only with TRACING_ECTO_ENABLED
               :"db.instance" => :anything,
               :"db.name" => :anything,
               :"db.system" => :anything,
               :"db.type" => :anything,
               # Ecto timing: the suffix comes from `:time_unit`, which
               # `Lightning.OpenTelemetry` leaves at its `:microsecond` default
               :decode_time_microseconds => :anything,
               # cowboy (stop/exception) and Oban (job exception)
               :"error.type" => :anything,
               # cowboy and Phoenix
               :"http.request.method" => :anything,
               :"http.response.status_code" => :anything,
               :"http.route" => :anything,
               # Ecto timing
               :idle_time_microseconds => :anything,
               # Oban job
               :"messaging.client.id" => :anything,
               :"messaging.destination.name" => :anything,
               :"messaging.message.id" => :anything,
               :"messaging.operation.name" => :anything,
               :"messaging.operation.type" => :anything,
               :"messaging.system" => :anything,
               # cowboy
               :"network.protocol.name" => :anything,
               :"network.protocol.version" => :anything,
               # Oban job
               :"oban.job.attempt" => :anything,
               :"oban.job.inserted_at" => :anything,
               :"oban.job.job_id" => :anything,
               :"oban.job.max_attempts" => :anything,
               :"oban.job.priority" => :anything,
               :"oban.job.scheduled_at" => :anything,
               :"oban.job.worker" => :anything,
               # Phoenix
               :"phoenix.action" => :atom,
               :"phoenix.plug" => :anything,
               # Ecto timing
               :query_time_microseconds => :anything,
               :queue_time_microseconds => :anything,
               # cowboy
               :"server.port" => :anything,
               # Ecto
               :source => :anything,
               :total_time_microseconds => :anything,
               # cowboy
               :"url.scheme" => :anything
             }
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

  # Does not (currently) resemble the ETS table that OT creates Used to confirm
  # that the temporary table created to hold scrubbed spans matches the input
  # table's type and key position.
  defp spurious_span_table do
    :ets.new(:spans, [
      :bag,
      {:keypos, span_rec(:instrumentation_scope) - 1}
    ])
  end
end
