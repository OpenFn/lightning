defmodule Lightning.Attempts.PromExPlugin do
  use PromEx.Plugin

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :rory_test,
      [
        distribution(
          [:lightning, :attempt, :queue, :delay, :milliseconds],
          event_name: [:domain, :attempt, :queue],
          measurement: :delay,
          description: "Queue delay for attempts",
          reporter_options: [
            buckets: exponential!(100, 2, 10)
          ],
          tags: [],
          unit: :millisecond
        )
      ]
    )
  end
end
