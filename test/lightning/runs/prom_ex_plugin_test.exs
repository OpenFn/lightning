defmodule Lightning.Runs.PromExPluginText do
  use Lightning.DataCase, async: false

  import Lightning.Factories
  import Mock

  alias Lightning.Runs.PromExPlugin

  @run_performance_age_seconds 4
  @stalled_run_threshold_seconds 333

  test "event_metrics returns a Promex Event" do
    event = PromExPlugin.event_metrics(plugin_config())

    assert event.group_name == :rory_test

    [metric | _] = event.metrics

    assert metric.description == "Queue delay for runs"
    assert metric.event_name == [:domain, :run, :queue]
    assert metric.measurement == :delay
    assert metric.name == [:lightning, :run, :queue, :delay, :milliseconds]

    assert metric.reporter_options == [
             buckets: [
               100,
               200,
               400,
               800,
               1_500,
               5_000,
               15_000,
               30_000,
               50_000,
               100_000
             ]
           ]

    assert metric.tags == []
    assert metric.unit == :millisecond
  end

  describe "polling_metrics" do
    test "returns a polling instance for stalled runs" do
      expected_mfa =
        {
          Lightning.Runs.PromExPlugin,
          :stalled_run_count,
          [@stalled_run_threshold_seconds]
        }

      stalled_run_polling =
        plugin_config() |> find_metric_group(:lightning_stalled_run_metrics)

      assert %PromEx.MetricTypes.Polling{
               poll_rate: 5000,
               measurements_mfa: ^expected_mfa,
               metrics: [metric | _]
             } = stalled_run_polling

      assert %Telemetry.Metrics.LastValue{
               name: [:lightning, :run, :queue, :stalled, :count],
               event_name: [:lightning, :run, :queue, :stalled],
               description: "The count of runs stuck in the `available` state",
               measurement: :count
             } = metric
    end

    test "returns a polling group for run queue metrics" do
      expected_mfa =
        {
          Lightning.Runs.PromExPlugin,
          :run_claim_duration,
          [@run_performance_age_seconds]
        }

      run_performance_polling =
        plugin_config() |> find_metric_group(:lightning_run_queue_metrics)

      assert %PromEx.MetricTypes.Polling{
               poll_rate: 5000,
               measurements_mfa: ^expected_mfa
             } = run_performance_polling
    end

    test "run queue metrics group includes claim duration metric" do
      %{metrics: metrics} =
        plugin_config() |> find_metric_group(:lightning_run_queue_metrics)

      metric =
        metrics
        |> find_metric([
          :lightning,
          :run,
          :queue,
          :claim,
          :average_duration,
          :milliseconds
        ])

      assert(
        %Telemetry.Metrics.LastValue{
          event_name: [:lightning, :run, :queue, :claim],
          description: "The average time taken before a run is claimed",
          measurement: :average_duration,
          unit: :millisecond
        } = metric
      )
    end

    defp find_metric_group(plugin_config, group_name) do
      plugin_config
      |> PromExPlugin.polling_metrics()
      |> Enum.find(fn
        %{group_name: ^group_name} -> true
        _ -> false
      end)
    end

    defp find_metric(metrics, metric_name) do
      metrics
      |> Enum.find(fn
        %{name: ^metric_name} -> true
        _ -> false
      end)
    end
  end

  describe "stalled_run_count" do
    setup do
      %{
        event: [:lightning, :run, :queue, :stalled],
        stall_threshold_seconds: 30
      }
    end

    test "fires a metric with the count of stalled runs",
         %{event: event, stall_threshold_seconds: stall_threshold_seconds} do
      ref = :telemetry_test.attach_event_handlers(self(), [event])

      now = DateTime.utc_now()
      _stalled_1 = available_run(now, -60)
      _stalled_2 = available_run(now, -50)
      _stalled_2 = available_run(now, -40)
      _not_stalled_due_to_time = available_run(now, -20)
      _not_stalled_due_to_state = claimed_run(now, -40)

      PromExPlugin.stalled_run_count(stall_threshold_seconds)

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
        PromExPlugin.stalled_run_count(stall_threshold_seconds)
      end

      refute_received {
        ^event,
        ^ref,
        %{count: _count},
        %{}
      }
    end

    defp claimed_run(now, time_offset) do
      insert(
        :run,
        state: :claimed,
        inserted_at: DateTime.add(now, time_offset),
        dataclip: build(:dataclip),
        starting_job: build(:job),
        work_order: build(:workorder)
      )
    end
  end

  describe ".run_claim_duration" do
    setup do
      %{event: [:lightning, :run, :queue, :claim], age: 20}
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

      _included_run_1 =
        other_run(now, eligible_offset, duration_until_claimed_1)

      _included_run_2 =
        other_run(now, eligible_offset, duration_until_claimed_2)

      _excluded_run_too_old = other_run(now, ineligible_offset, 100)

      expected_performance_ms =
        (duration_until_claimed_1 + duration_until_claimed_2) * 1000 / 2

      PromExPlugin.run_claim_duration(age)

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
        PromExPlugin.run_claim_duration(age)
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
      %{reference: DateTime.utc_now(), run_age: 10}
    end

    test "returns average duration for unclaimed and claimed runs",
         %{reference: reference, run_age: run_age} do
      threshold = reference |> DateTime.add(-run_age)

      duration_until_claimed_1 = 1
      duration_until_claimed_2 = 2

      before_threshold_offset = -1
      on_threshold_offset = 0
      after_threshold_offset = 1

      _included_available_1 =
        available_run(threshold, before_threshold_offset)

      available_duration_1 =
        reference
        |> DateTime.diff(DateTime.add(threshold, before_threshold_offset))

      _included_available_2 =
        available_run(threshold, after_threshold_offset)

      available_duration_2 =
        reference
        |> DateTime.diff(DateTime.add(threshold, after_threshold_offset))

      _included_other_1 =
        other_run(
          threshold,
          after_threshold_offset,
          duration_until_claimed_1
        )

      _included_other_2 =
        other_run(
          threshold,
          after_threshold_offset,
          duration_until_claimed_2
        )

      _excluded_other_too_old_1 =
        other_run(threshold, before_threshold_offset, 1000)

      _excluded_other_too_old_2 =
        other_run(threshold, on_threshold_offset, 1001)

      total_durations =
        available_duration_1 +
          available_duration_2 +
          duration_until_claimed_1 +
          duration_until_claimed_2

      expected_average_duration_ms = total_durations * 1000 / 4

      average_duration =
        PromExPlugin.calculate_average_claim_duration(reference, run_age)

      assert average_duration == expected_average_duration_ms
    end

    test "returns 0 if there are no eligible runs",
         %{reference: reference, run_age: run_age} do
      average_duration =
        PromExPlugin.calculate_average_claim_duration(reference, run_age)

      assert average_duration == 0.0
    end
  end

  defp available_run(now, time_offset) do
    insert(
      :run,
      state: :available,
      inserted_at: DateTime.add(now, time_offset),
      dataclip: build(:dataclip),
      starting_job: build(:job),
      work_order: build(:workorder)
    )
  end

  defp other_run(now, inserted_at_time_offset, duration_until_claimed) do
    inserted_at = DateTime.add(now, inserted_at_time_offset)
    claimed_at = DateTime.add(inserted_at, duration_until_claimed)

    insert(
      :run,
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
      {:run_performance_age_seconds, @run_performance_age_seconds},
      {:stalled_run_threshold_seconds, @stalled_run_threshold_seconds}
    ]
  end
end
