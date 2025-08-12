defmodule Lightning.PromExPluginTest do
  use Lightning.DataCase, async: true

  alias Lightning.PromExTestPlugin

  describe "event_metrics/1" do
    test "returns a single event group" do
      assert [
               %PromEx.MetricTypes.Event{
                 group_name: :lightning_prom_ex_test_metrics
               }
             ] = PromExTestPlugin.event_metrics([])
    end

    test "contains a counter metric for test purposes" do
      expected_name = [:lightning, :prom_ex_test, :count]

      expected_description =
        "A counter that can be triggered arbitrarily for test purposes."

      PromExTestPlugin.event_metrics([])
      |> assert_counter(expected_name, expected_description)
    end

    test "contains a last value metric for test purposes" do
      expected_name = [:lightning, :prom_ex_test, :last_value]

      expected_description =
        "A gauge that can be triggered arbitrarily for test purposes."

      PromExTestPlugin.event_metrics([])
      |> assert_last_value(expected_name, expected_description)
    end

    def assert_counter([%{metrics: metrics}], name, description) do
      assert [counter] =
               metrics
               |> Enum.filter(fn
                 %Telemetry.Metrics.Counter{} -> true
                 _ -> false
               end)

      assert counter.name == name
      assert counter.description == description
      assert counter.tags == []
    end

    def assert_last_value([%{metrics: metrics}], name, description) do
      assert [last_value] =
               metrics
               |> Enum.filter(fn
                 %Telemetry.Metrics.LastValue{} -> true
                 _ -> false
               end)

      assert last_value.name == name
      assert last_value.description == description
      assert last_value.tags == []
    end
  end

  describe "fire_counter_event/0" do
    test "increments the counter when fired" do
      event = [:lightning, :prom_ex_test]

      ref = :telemetry_test.attach_event_handlers(self(), [event])

      PromExTestPlugin.fire_counter_event()

      assert_received {
        ^event,
        ^ref,
        %{count: 1},
        %{}
      }
    end
  end

  describe "seed_event_metrics/0" do
    test "fires a counter event" do
      event = [:lightning, :prom_ex_test]

      ref = :telemetry_test.attach_event_handlers(self(), [event])

      PromExTestPlugin.seed_event_metrics()

      assert_received {
        ^event,
        ^ref,
        %{count: 1},
        %{}
      }
    end
  end

  describe "fire_gauge_event/1" do
    test "sets the gauge event value" do
      event = [:lightning, :prom_ex_test]

      ref = :telemetry_test.attach_event_handlers(self(), [event])

      PromExTestPlugin.fire_gauge_event(42)

      assert_received {
        ^event,
        ^ref,
        %{last_value: 42},
        %{}
      }
    end
  end
end
