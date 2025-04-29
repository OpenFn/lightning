defmodule Lightning.Runs.PromExPluginText do
  use Lightning.DataCase, async: false

  import Lightning.Factories
  import Mock

  alias Lightning.Run
  alias Lightning.Runs.PromExPlugin

  require Run

  @queue_metrics_period_seconds 5
  @poll_rate @queue_metrics_period_seconds * 1000
  @run_performance_age_seconds 4
  @stalled_run_threshold_seconds 333

  describe "event_metrics/1" do
    test "returns a single event group" do
      assert [
               %PromEx.MetricTypes.Event{
                 group_name: :lightning_run_event_metrics
               }
             ] = PromExPlugin.event_metrics(plugin_config())
    end

    test "returns a distribution metric for run queue delay" do
      [%{metrics: metrics}] = PromExPlugin.event_metrics(plugin_config())

      metric =
        metrics
        |> find_event_metric([:lightning, :run, :queue, :delay, :milliseconds])

      assert metric.event_name == [:domain, :run, :queue]
      assert metric.measurement == :delay

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

    test "returns a counter metric to track lost runs" do
      [%{metrics: metrics}] = PromExPlugin.event_metrics(plugin_config())

      metric =
        metrics
        |> find_event_metric([:lightning, :run, :lost, :count])

      assert metric.description == "A counter of lost runs."
      assert metric.event_name == [:lightning, :run, :lost]
      assert metric.tags == [:seed_event, :state, :worker_name]
    end

    def find_event_metric(metrics, metric_name) do
      assert [candidate] =
               metrics
               |> Enum.filter(fn metric ->
                 metric.name == metric_name
               end)

      candidate
    end
  end

  test "event_metrics returns a Promex Event" do
    [event] = PromExPlugin.event_metrics(plugin_config())

    assert event.group_name == :lightning_run_event_metrics

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
               poll_rate: @poll_rate,
               measurements_mfa:
                 {PromEx.MetricTypes.Polling, :safe_polling_runner,
                  [^expected_mfa]},
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
          :run_queue_metrics,
          [@run_performance_age_seconds, @queue_metrics_period_seconds]
        }

      run_performance_polling =
        plugin_config() |> find_metric_group(:lightning_run_queue_metrics)

      assert %PromEx.MetricTypes.Polling{
               poll_rate: @poll_rate,
               measurements_mfa:
                 {PromEx.MetricTypes.Polling, :safe_polling_runner,
                  [^expected_mfa]}
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

    test "run queue metrics group includes number of available runs" do
      %{metrics: metrics} =
        plugin_config() |> find_metric_group(:lightning_run_queue_metrics)

      metric =
        metrics
        |> find_metric([
          :lightning,
          :run,
          :queue,
          :available,
          :count
        ])

      assert(
        %Telemetry.Metrics.LastValue{
          event_name: [:lightning, :run, :queue, :available],
          description: "The number of available runs in the queue",
          measurement: :count
        } = metric
      )
    end

    test "run queue metrics group includes number of runs finalised" do
      %{metrics: metrics} =
        plugin_config() |> find_metric_group(:lightning_run_queue_metrics)

      metric =
        metrics
        |> find_metric([
          :lightning,
          :run,
          :queue,
          :finalised,
          :count
        ])

      assert(
        %Telemetry.Metrics.LastValue{
          event_name: [:lightning, :run, :queue, :finalised],
          description:
            "The number of runs finalised during the consideration window",
          measurement: :count
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

  describe ".run_queue_metrics" do
    setup do
      %{
        age: 20,
        available_event: [:lightning, :run, :queue, :available],
        claim_event: [:lightning, :run, :queue, :claim],
        finalised_event: [:lightning, :run, :queue, :finalised]
      }
    end

    test "triggers a metric that returns the average queue delay", config do
      %{claim_event: event, age: age} = config

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

      PromExPlugin.run_queue_metrics(age, @queue_metrics_period_seconds)

      assert_received {
        ^event,
        ^ref,
        %{average_duration: ^expected_performance_ms},
        %{}
      }
    end

    test "triggers a metric with the number of available runs", config do
      %{available_event: event, age: age} = config

      ref =
        :telemetry_test.attach_event_handlers(
          self(),
          [event]
        )

      now = DateTime.utc_now()
      _available_run_1 = available_run(now, 0)
      _available_run_2 = available_run(now, 0)
      _available_run_3 = available_run(now, 0)
      _other_run = other_run(now, 0, 0)

      PromExPlugin.run_queue_metrics(age, @queue_metrics_period_seconds)

      assert_received {
        ^event,
        ^ref,
        %{count: 3},
        %{}
      }
    end

    test "triggers a metric to count finalised runs", config do
      %{finalised_event: event, age: age} = config

      ref =
        :telemetry_test.attach_event_handlers(
          self(),
          [event]
        )

      now = DateTime.utc_now()

      _excluded_not_finalised =
        now |> run_with_finished_at(0, :available)

      _excluded_outside_window =
        now
        |> run_with_finished_at(-(@queue_metrics_period_seconds + 1), :success)

      _included_finalised_1 =
        now
        |> run_with_finished_at(0, :cancelled)

      _included_finalised_2 =
        now
        |> run_with_finished_at(0, :success)

      _included_finalised_3 =
        now
        |> run_with_finished_at(0, :failed)

      PromExPlugin.run_queue_metrics(age, @queue_metrics_period_seconds)

      assert_received {
        ^event,
        ^ref,
        %{count: 3},
        %{}
      }
    end

    test "doesn't trigger metrics if Repo is unavailable", config do
      # This scenario occurs during server startup

      %{
        age: age,
        available_event: available_event,
        claim_event: claim_event
      } = config

      ref =
        :telemetry_test.attach_event_handlers(
          self(),
          [available_event, claim_event]
        )

      with_mock(
        Process,
        [:passthrough],
        whereis: fn _name -> nil end
      ) do
        PromExPlugin.run_queue_metrics(age, @queue_metrics_period_seconds)
      end

      refute_received {
        ^available_event,
        ^ref,
        %{count: _count},
        %{}
      }

      refute_received {
        ^claim_event,
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

  describe ".count_finalised_runs" do
    test "triggers an event counting all runs finalised within the window" do
      now = DateTime.utc_now()
      window_seconds = 10
      include_offset = -(window_seconds - 1)
      exclude_offset = -(window_seconds + 1)
      final_states = Run.final_states()

      finalised_count = Enum.count(final_states)

      assert finalised_count > 0

      # Build the finalised runs
      for state <- final_states do
        now |> run_with_finished_at(include_offset, state)
      end

      _excluded_outside_window_1 =
        now |> run_with_finished_at(exclude_offset, hd(final_states))

      _excluded_outside_window_2 =
        now |> run_with_finished_at(exclude_offset, hd(final_states))

      _excluded_not_finalised =
        now |> run_with_finished_at(include_offset, :available)

      threshold_time = DateTime.add(now, -window_seconds)

      assert(
        PromExPlugin.count_finalised_runs(threshold_time) == finalised_count
      )
    end
  end

  describe "seed_event_metrics/0" do
    test "seeds the lost runs counter" do
      event = [:lightning, :run, :lost]

      ref = :telemetry_test.attach_event_handlers(self(), [event])

      Lightning.Runs.PromExPlugin.seed_event_metrics()

      assert_received {
        ^event,
        ^ref,
        %{count: 1},
        %{seed_event: true, state: "n/a", worker_name: "n/a"}
      }
    end
  end

  describe "fire_lost_run_event" do
    setup do
      event = [:lightning, :run, :lost]

      ref = :telemetry_test.attach_event_handlers(self(), [event])

      %{
        event: event,
        ref: ref,
        state: :claimed,
        state_as_string: "claimed",
        worker_name: "worker_1"
      }
    end

    test "defaults to a non-seed event", %{
      event: event,
      ref: ref,
      state: state,
      state_as_string: state_as_string,
      worker_name: worker_name
    } do
      Lightning.Runs.PromExPlugin.fire_lost_run_event(worker_name, state)

      assert_received {
        ^event,
        ^ref,
        %{count: 1},
        %{seed_event: false, state: ^state_as_string, worker_name: ^worker_name}
      }
    end

    test "can set a seed event", %{
      event: event,
      ref: ref,
      state: state,
      state_as_string: state_as_string,
      worker_name: worker_name
    } do
      Lightning.Runs.PromExPlugin.fire_lost_run_event(worker_name, state, true)

      assert_received {
        ^event,
        ^ref,
        %{count: 1},
        %{seed_event: true, state: ^state_as_string, worker_name: ^worker_name}
      }
    end

    test "can set a non-seed event", %{
      event: event,
      ref: ref,
      state: state,
      state_as_string: state_as_string,
      worker_name: worker_name
    } do
      Lightning.Runs.PromExPlugin.fire_lost_run_event(worker_name, state, false)

      assert_received {
        ^event,
        ^ref,
        %{count: 1},
        %{seed_event: false, state: ^state_as_string, worker_name: ^worker_name}
      }
    end

    test "converts a nil worker name", %{
      event: event,
      ref: ref,
      state: state,
      state_as_string: state_as_string
    } do
      Lightning.Runs.PromExPlugin.fire_lost_run_event(nil, state)

      assert_received {
        ^event,
        ^ref,
        %{count: 1},
        %{seed_event: false, state: ^state_as_string, worker_name: "n/a"}
      }
    end

    test "converts a nil state", %{
      event: event,
      ref: ref,
      worker_name: worker_name
    } do
      Lightning.Runs.PromExPlugin.fire_lost_run_event(worker_name, nil)

      assert_received {
        ^event,
        ^ref,
        %{count: 1},
        %{seed_event: false, state: "n/a", worker_name: ^worker_name}
      }
    end

    test "accepts a state that is a string", %{
      event: event,
      ref: ref,
      state_as_string: state_as_string,
      worker_name: worker_name
    } do
      Lightning.Runs.PromExPlugin.fire_lost_run_event(
        worker_name,
        state_as_string
      )

      assert_received {
        ^event,
        ^ref,
        %{count: 1},
        %{seed_event: false, state: ^state_as_string, worker_name: ^worker_name}
      }
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

  defp run_with_finished_at(now, finished_at_offset, state) do
    inserted_at = DateTime.add(now, -100)
    finished_at = DateTime.add(now, finished_at_offset)

    insert(
      :run,
      state: state,
      inserted_at: inserted_at,
      finished_at: finished_at,
      dataclip: build(:dataclip),
      starting_job: build(:job),
      work_order: build(:workorder)
    )
  end

  defp plugin_config do
    [
      {:run_performance_age_seconds, @run_performance_age_seconds},
      {:run_queue_metrics_period_seconds, @queue_metrics_period_seconds},
      {:stalled_run_threshold_seconds, @stalled_run_threshold_seconds}
    ]
  end
end
