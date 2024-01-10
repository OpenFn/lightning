defmodule Lightning.Attempts.PromExPluginText do
  use Lightning.DataCase, async: false

  import Lightning.Factories
  import Mock

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

  test "polling_metrics returns a Promex Polling instance" do
    threshold_seconds = 333

    expected_mfa =
      {
        Lightning.Attempts.PromExPlugin,
        :stalled_attempt_count,
        [threshold_seconds]
      }

    [stalled_attempt_polling | _] =
      PromExPlugin.polling_metrics(
        stalled_attempt_threshold_seconds: threshold_seconds
      )

    assert %PromEx.MetricTypes.Polling{
             group_name: :lightning_attempt_polling_events,
             poll_rate: 5000,
             measurements_mfa: ^expected_mfa,
             metrics: [metric | _]
           } = stalled_attempt_polling

    assert %Telemetry.Metrics.LastValue{
             name: [:lightning, :attempt, :queue, :stalled, :count],
             event_name: [:lightning, :attempt, :queue, :stalled],
             description: "The count of attempts stuck in the `available` state",
             measurement: :count
           } = metric
  end

  describe "stalled_attempt_count" do
    test "fires a metric with the count of stalled attempts" do
      ref =
        :telemetry_test.attach_event_handlers(
          self(),
          [[:lightning, :attempt, :queue, :stalled]]
        )

      stall_threshold_seconds = 30

      now = DateTime.utc_now()
      _stalled_1 = available_attempt(now, -60)
      _stalled_2 = available_attempt(now, -50)
      _stalled_2 = available_attempt(now, -40)
      _not_stalled_due_to_time = available_attempt(now, -20)
      _not_stalled_due_to_state = claimed_attempt(now, -40)

      PromExPlugin.stalled_attempt_count(stall_threshold_seconds)

      assert_received {
        [:lightning, :attempt, :queue, :stalled],
        ^ref,
        %{count: 3},
        %{}
      }
    end

    test "does not fire a metric if the Repo is not available when called" do
      # This scenario occurs during server startup
      ref =
        :telemetry_test.attach_event_handlers(
          self(),
          [[:lightning, :attempt, :queue, :stalled]]
        )

      stall_threshold_seconds = 30

      with_mock(
        Process,
        [:passthrough],
        whereis: fn _name -> nil end
      ) do
        PromExPlugin.stalled_attempt_count(stall_threshold_seconds)
      end

      refute_received {
        [:lightning, :attempt, :queue, :stalled],
        ^ref,
        %{count: _count},
        %{}
      }
    end

    defp available_attempt(now, time_offset) do
      insert(
        :attempt,
        state: :available,
        inserted_at: DateTime.add(now, time_offset),
        dataclip: build(:dataclip),
        starting_job: build(:job),
        work_order: build(:workorder)
      )
    end

    defp claimed_attempt(now, time_offset) do
      insert(
        :attempt,
        state: :claimed,
        inserted_at: DateTime.add(now, time_offset),
        dataclip: build(:dataclip),
        starting_job: build(:job),
        work_order: build(:workorder)
      )
    end
  end
end
