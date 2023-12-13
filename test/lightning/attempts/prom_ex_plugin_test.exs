defmodule Lightning.Attempts.PromExPluginText do
  use ExUnit.Case, async: true

  alias Lightning.Attempts.PromExPlugin

  test "event_metrics returns a Promex Event" do
    event = PromExPlugin.event_metrics(%{})

    assert event.group_name == :rory_test

    [metric | _] = event.metrics

    assert metric.description == "Queue delay for attempts"
    assert metric.event_name == [:domain, :attempt, :queue]
    assert metric.measurement == :delay
    assert metric.name == [:lightning, :attempt, :queue, :delay, :milliseconds]

    assert metric.reporter_options == [
             buckets: [
               100,
               200,
               400,
               800,
               1600,
               3200,
               6400,
               12800,
               25600,
               51200
             ]
           ]

    assert metric.tags == []
    assert metric.unit == :millisecond
  end
end
