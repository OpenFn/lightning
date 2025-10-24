defmodule Lightning.PromExTestPlugin do
  @moduledoc """
  A PromEx plugin that contains metrics that can be used to test
  infrastructure integration.
  """
  use PromEx.Plugin

  alias Telemetry.Metrics

  @event_name [:lightning, :prom_ex_test]

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :lightning_prom_ex_test_metrics,
        [
          Metrics.counter(
            @event_name ++ [:count],
            description:
              "A counter that can be triggered arbitrarily for test purposes."
          ),
          Metrics.last_value(
            @event_name ++ [:last_value],
            description:
              "A gauge that can be triggered arbitrarily for test purposes."
          )
        ]
      )
    ]
  end

  def fire_counter_event do
    :telemetry.execute(
      @event_name,
      %{count: 1},
      %{}
    )
  end

  def fire_gauge_event(last_value) do
    :telemetry.execute(
      @event_name,
      %{last_value: last_value},
      %{}
    )
  end

  def seed_event_metrics do
    fire_counter_event()
  end
end
