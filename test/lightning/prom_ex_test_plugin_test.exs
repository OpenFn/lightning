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

    test "returns event metrics useful for manual/integration testing" do
      [%{metrics: [metric]}] = PromExTestPlugin.event_metrics([])

      assert %Telemetry.Metrics.Counter{} = metric
      assert metric.name == [:lightning, :prom_ex_test, :count]

      assert metric.description ==
               "A counter that can be triggered arbitrarily for test purposes."

      assert metric.tags == []
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
end
