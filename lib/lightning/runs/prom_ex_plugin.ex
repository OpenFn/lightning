defmodule Lightning.Runs.PromExPlugin do
  @moduledoc """
  Metrics callbacks implementation for the PromEx plugin.

  Event metrics are used to publish the dispatched events in the system.
  Polling metrics are used to publish metrics that are calculated by polling data periodically.
  """
  use PromEx.Plugin

  import Ecto.Query

  alias Lightning.Repo
  alias Lightning.Run
  alias Lightning.Runs.PromExPlugin.ImpededProjectHelper
  alias Telemetry.Metrics

  @available_count_event [:lightning, :run, :queue, :available]
  @average_claim_event [:lightning, :run, :queue, :claim]
  @finalised_count_event [:lightning, :run, :queue, :finalised]
  @impeded_project_event [:lightning, :run, :project, :impeded]
  @lost_run_event [:lightning, :run, :lost]
  @stalled_event [:lightning, :run, :queue, :stalled]

  @impl true
  def event_metrics(_opts) do
    [
      Event.build(
        :lightning_run_event_metrics,
        [
          distribution(
            [:lightning, :run, :queue, :delay, :milliseconds],
            event_name: [:domain, :run, :queue],
            measurement: :delay,
            description: "Queue delay for runs",
            reporter_options: [
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
            ],
            tags: [],
            unit: :millisecond
          ),
          Metrics.counter(
            @lost_run_event ++ [:count],
            description: "A counter of lost runs."
          )
        ]
      )
    ]
  end

  def seed_event_metrics, do: fire_lost_run_event()

  def fire_lost_run_event do
    :telemetry.execute(
      @lost_run_event,
      %{count: 1},
      %{}
    )
  end

  @impl true
  def polling_metrics(opts) do
    {:ok, stalled_run_threshold_seconds} =
      opts |> Keyword.fetch(:stalled_run_threshold_seconds)

    {:ok, run_performance_age_seconds} =
      opts |> Keyword.fetch(:run_performance_age_seconds)

    {:ok, run_queue_metrics_period_seconds} =
      opts |> Keyword.fetch(:run_queue_metrics_period_seconds)

    {:ok, unclaimed_run_threshold_seconds} =
      opts |> Keyword.fetch(:unclaimed_run_threshold_seconds)

    [
      stalled_run_metrics(
        stalled_run_threshold_seconds,
        run_queue_metrics_period_seconds
      ),
      run_performance_metrics(
        run_performance_age_seconds,
        run_queue_metrics_period_seconds
      )
    ] ++
      project_polling_metrics(
        Lightning.Config.promex_expensive_metrics_enabled?(),
        unclaimed_run_threshold_seconds,
        run_queue_metrics_period_seconds
      )
  end

  defp stalled_run_metrics(threshold_seconds, period_in_seconds) do
    Polling.build(
      :lightning_stalled_run_metrics,
      period_in_seconds * 1000,
      {__MODULE__, :stalled_run_count, [threshold_seconds]},
      [
        last_value(
          [:lightning, :run, :queue, :stalled, :count],
          event_name: @stalled_event,
          description: "The count of runs stuck in the `available` state",
          measurement: :count
        )
      ],
      detach_on_error: false
    )
  end

  def stalled_run_count(threshold_seconds) do
    trigger_stalled_run_metric(Process.whereis(Repo), threshold_seconds)
  end

  defp trigger_stalled_run_metric(nil, _threshold_seconds) do
    nil
  end

  defp trigger_stalled_run_metric(repo_pid, threshold_seconds) do
    check_repo_state(repo_pid)

    threshold_time =
      DateTime.utc_now()
      |> DateTime.add(-1 * threshold_seconds)

    query =
      from a in Run,
        select: count(a.id),
        where: a.state == :available,
        where: a.inserted_at < ^threshold_time

    count = Repo.one(query)

    :telemetry.execute(@stalled_event, %{count: count}, %{})
  end

  defp run_performance_metrics(run_age_seconds, period_in_seconds) do
    Polling.build(
      :lightning_run_queue_metrics,
      period_in_seconds * 1000,
      {__MODULE__, :run_queue_metrics, [run_age_seconds, period_in_seconds]},
      [
        last_value(
          [
            :lightning,
            :run,
            :queue,
            :claim,
            :average_duration,
            :milliseconds
          ],
          event_name: @average_claim_event,
          description: "The average time taken before a run is claimed",
          measurement: :average_duration,
          unit: :millisecond
        ),
        last_value(
          [:lightning, :run, :queue, :available, :count],
          event_name: @available_count_event,
          description: "The number of available runs in the queue",
          measurement: :count
        ),
        last_value(
          [:lightning, :run, :queue, :finalised, :count],
          event_name: @finalised_count_event,
          description:
            "The number of runs finalised during the consideration window",
          measurement: :count
        )
      ],
      detach_on_error: false
    )
  end

  def run_queue_metrics(run_age_seconds, consideration_window_seconds) do
    if repo_pid = Process.whereis(Repo) do
      check_repo_state(repo_pid)

      trigger_run_claim_duration(run_age_seconds)
      trigger_available_runs_count()

      trigger_finalised_runs_count(
        DateTime.utc_now()
        |> DateTime.add(-consideration_window_seconds)
      )
    end
  end

  defp trigger_run_claim_duration(run_age_seconds) do
    average_duration =
      calculate_average_claim_duration(DateTime.utc_now(), run_age_seconds)

    :telemetry.execute(
      @average_claim_event,
      %{average_duration: average_duration},
      %{}
    )
  end

  def calculate_average_claim_duration(reference_time, run_age_seconds) do
    threshold_time = reference_time |> DateTime.add(-run_age_seconds)

    # Available runs: duration = reference_time - inserted_at (in milliseconds)
    available_query =
      from r in Run,
        where: r.state == :available,
        select: %{
          duration_ms:
            fragment(
              "EXTRACT(EPOCH FROM (? - ?)) * 1000",
              type(^reference_time, :utc_datetime_usec),
              r.inserted_at
            )
        }

    # Recently processed runs: duration = claimed_at - inserted_at (in milliseconds)
    processed_query =
      from r in Run,
        where: r.state != :available and r.inserted_at > ^threshold_time,
        select: %{
          duration_ms:
            fragment(
              "EXTRACT(EPOCH FROM (? - ?)) * 1000",
              r.claimed_at,
              r.inserted_at
            )
        }

    # Combine with UNION ALL and calculate average
    union_query = union_all(available_query, ^processed_query)

    from(u in subquery(union_query), select: avg(u.duration_ms))
    |> Repo.one()
    |> to_rounded_float()
  end

  defp to_rounded_float(%Decimal{} = d),
    do: d |> Decimal.to_float() |> Float.round(0)

  defp to_rounded_float(f) when is_float(f), do: Float.round(f, 0)
  defp to_rounded_float(nil), do: 0.0

  defp check_repo_state(repo_pid) do
    # NOTE: During local testing of server starts, having the pid was not enough
    # a call to .get_state was also required, otherwise the metric triggers before
    # the Repo GenServer is available.

    :sys.get_state(repo_pid)
  end

  defp trigger_available_runs_count do
    query = from r in Run, where: r.state == :available

    :telemetry.execute(
      @available_count_event,
      %{count: Repo.aggregate(query, :count)},
      %{}
    )
  end

  defp trigger_finalised_runs_count(threshold_time) do
    count = count_finalised_runs(threshold_time)

    :telemetry.execute(
      @finalised_count_event,
      %{count: count},
      %{}
    )
  end

  def count_finalised_runs(threshold_time) do
    final_states = Run.final_states()

    query =
      from r in Run,
        where: r.state in ^final_states,
        where: r.finished_at > ^threshold_time

    query |> Repo.aggregate(:count)
  end

  defp project_polling_metrics(
         false,
         _unclaimed_threshold_seconds,
         _period_in_seconds
       ) do
    []
  end

  defp project_polling_metrics(
         true,
         unclaimed_threshold_seconds,
         period_in_seconds
       ) do
    [
      Polling.build(
        :lightning_run_project_metrics,
        period_in_seconds * 1000,
        {__MODULE__, :project_metrics, [unclaimed_threshold_seconds]},
        [
          last_value(
            @impeded_project_event ++ [:count],
            description:
              "The count of projects impeded due to lack of worker capacity"
          )
        ],
        detach_on_error: false
      )
    ]
  end

  def project_metrics(unclaimed_threshold_seconds) do
    if repo = Process.whereis(Repo) do
      check_repo_state(repo)

      threshold_time =
        DateTime.add(Lightning.current_time(), -unclaimed_threshold_seconds)

      count =
        threshold_time
        |> ImpededProjectHelper.workflows_with_available_runs_older_than()
        |> ImpededProjectHelper.find_projects_with_unused_concurrency()
        |> Enum.count()

      :telemetry.execute(
        @impeded_project_event,
        %{count: count},
        %{}
      )
    end
  end
end
