defmodule Lightning.Attempts.PromExPluginText do
  use Lightning.DataCase, async: false

  import Lightning.Factories
  import Mock

  alias Lightning.Attempts.PromExPlugin

  @attempt_performance_age_seconds 4
  @stalled_attempt_threshold_seconds 333

  test "event_metrics returns a Promex Event" do
    event = PromExPlugin.event_metrics(plugin_config())

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

  describe "polling_metrics" do
    test "returns a polling instance for stalled attempts" do
      expected_mfa =
        {
          Lightning.Attempts.PromExPlugin,
          :stalled_attempt_count,
          [@stalled_attempt_threshold_seconds]
        }

      [stalled_attempt_polling | _] =
        PromExPlugin.polling_metrics(plugin_config())

      assert %PromEx.MetricTypes.Polling{
               group_name: :lightning_stalled_attempt_metrics,
               poll_rate: 5000,
               measurements_mfa: ^expected_mfa,
               metrics: [metric | _]
             } = stalled_attempt_polling

      assert %Telemetry.Metrics.LastValue{
               name: [:lightning, :attempt, :queue, :stalled, :count],
               event_name: [:lightning, :attempt, :queue, :stalled],
               description:
                 "The count of attempts stuck in the `available` state",
               measurement: :count
             } = metric
    end

    test "returns a polling instance for attempt performance" do
      expected_mfa =
        {
          Lightning.Attempts.PromExPlugin,
          :attempt_claim_duration,
          [@attempt_performance_age_seconds]
        }

      [_ | [attempt_performance_polling]] =
        PromExPlugin.polling_metrics(plugin_config())

      assert %PromEx.MetricTypes.Polling{
               group_name: :lightning_attempt_queue_metrics,
               poll_rate: 5000,
               measurements_mfa: ^expected_mfa,
               metrics: [metric | _]
             } = attempt_performance_polling

      assert %Telemetry.Metrics.LastValue{
               name: [
                 :lightning,
                 :attempt,
                 :queue,
                 :claim,
                 :average_duration,
                 :milliseconds
               ],
               event_name: [:lightning, :attempt, :queue, :claim],
               description:
                 "The average time taken before a run is claimed",
               measurement: :average_duration,
               unit: :millisecond
             } = metric
    end
  end

  describe "stalled_attempt_count" do
    setup do
      %{
        event: [:lightning, :attempt, :queue, :stalled],
        stall_threshold_seconds: 30
      }
    end

    test "fires a metric with the count of stalled attempts",
         %{event: event, stall_threshold_seconds: stall_threshold_seconds} do
      ref = :telemetry_test.attach_event_handlers(self(), [event])

      now = DateTime.utc_now()
      _stalled_1 = available_attempt(now, -60)
      _stalled_2 = available_attempt(now, -50)
      _stalled_2 = available_attempt(now, -40)
      _not_stalled_due_to_time = available_attempt(now, -20)
      _not_stalled_due_to_state = claimed_attempt(now, -40)

      PromExPlugin.stalled_attempt_count(stall_threshold_seconds)

      assert_received {
        ^event,
        ^ref,
        %{count: 3},
        %{}
      }
    end

    test "does not fire a metric if the Repo is not available when called",
         %{event: event, stall_threshold_seconds: stall_threshold_seconds} do
      # This scenario occurs during server startup
      ref = :telemetry_test.attach_event_handlers(self(), [event])

      with_mock(
        Process,
        [:passthrough],
        whereis: fn _name -> nil end
      ) do
        PromExPlugin.stalled_attempt_count(stall_threshold_seconds)
      end

      refute_received {
        ^event,
        ^ref,
        %{count: _count},
        %{}
      }
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

  describe ".attempt_claim_duration" do
    setup do
      %{event: [:lightning, :attempt, :queue, :claim], age: 20}
    end

    test "executes a metric that returns the average queue delay",
         %{event: event, age: age} do
      # Comfortable offset in the hopes it will prevent flickering
      eligible_offset = -(age - 10)
      ineligible_offset = -(age + 1)
      duration_until_claimed_1 = 1
      duration_until_claimed_2 = 2
      now = DateTime.utc_now()

      ref =
        :telemetry_test.attach_event_handlers(
          self(),
          [event]
        )

      _included_attempt_1 =
        other_attempt(now, eligible_offset, duration_until_claimed_1)

      _included_attempt_2 =
        other_attempt(now, eligible_offset, duration_until_claimed_2)

      _excluded_attempt_too_old = other_attempt(now, ineligible_offset, 100)

      expected_performance_ms =
        (duration_until_claimed_1 + duration_until_claimed_2) * 1000 / 2

      PromExPlugin.attempt_claim_duration(age)

      assert_received {
        ^event,
        ^ref,
        %{average_duration: ^expected_performance_ms},
        %{}
      }
    end

    test "does not fire a metric if the Repo is not available when called",
         %{event: event, age: age} do
      # This scenario occurs during server startup
      ref =
        :telemetry_test.attach_event_handlers(
          self(),
          [event]
        )

      with_mock(
        Process,
        [:passthrough],
        whereis: fn _name -> nil end
      ) do
        PromExPlugin.attempt_claim_duration(age)
      end

      refute_received {
        ^event,
        ^ref,
        %{average_duration: _duration},
        %{}
      }
    end
  end

  describe ".calculate_average_claim_duration" do
    setup do
      %{reference: DateTime.utc_now(), attempt_age: 10}
    end

    test "returns average duration for unclaimed and claimed attempts",
         %{reference: reference, attempt_age: attempt_age} do
      threshold = reference |> DateTime.add(-attempt_age)

      duration_until_claimed_1 = 1
      duration_until_claimed_2 = 2

      before_threshold_offset = -1
      on_threshold_offset = 0
      after_threshold_offset = 1

      _included_available_1 =
        available_attempt(threshold, before_threshold_offset)

      available_duration_1 =
        reference
        |> DateTime.diff(DateTime.add(threshold, before_threshold_offset))

      _included_available_2 =
        available_attempt(threshold, after_threshold_offset)

      available_duration_2 =
        reference
        |> DateTime.diff(DateTime.add(threshold, after_threshold_offset))

      _included_other_1 =
        other_attempt(
          threshold,
          after_threshold_offset,
          duration_until_claimed_1
        )

      _included_other_2 =
        other_attempt(
          threshold,
          after_threshold_offset,
          duration_until_claimed_2
        )

      _excluded_other_too_old_1 =
        other_attempt(threshold, before_threshold_offset, 1000)

      _excluded_other_too_old_2 =
        other_attempt(threshold, on_threshold_offset, 1001)

      total_durations =
        available_duration_1 +
          available_duration_2 +
          duration_until_claimed_1 +
          duration_until_claimed_2

      expected_average_duration_ms = total_durations * 1000 / 4

      average_duration =
        PromExPlugin.calculate_average_claim_duration(reference, attempt_age)

      assert average_duration == expected_average_duration_ms
    end

    test "returns 0 if there are no eligible attempts",
         %{reference: reference, attempt_age: attempt_age} do
      average_duration =
        PromExPlugin.calculate_average_claim_duration(reference, attempt_age)

      assert average_duration == 0.0
    end
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

  defp other_attempt(now, inserted_at_time_offset, duration_until_claimed) do
    inserted_at = DateTime.add(now, inserted_at_time_offset)
    claimed_at = DateTime.add(inserted_at, duration_until_claimed)

    insert(
      :attempt,
      state: :claimed,
      inserted_at: inserted_at,
      claimed_at: claimed_at,
      dataclip: build(:dataclip),
      starting_job: build(:job),
      work_order: build(:workorder)
    )
  end

  defp plugin_config do
    [
      {:attempt_performance_age_seconds, @attempt_performance_age_seconds},
      {:stalled_attempt_threshold_seconds, @stalled_attempt_threshold_seconds}
    ]
  end
end
