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

  @available_count_event [:lightning, :run, :queue, :available]
  @average_claim_event [:lightning, :run, :queue, :claim]
  @stalled_event [:lightning, :run, :queue, :stalled]

  @impl true
  def event_metrics(_opts) do
    Event.build(
      :rory_test,
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
        )
      ]
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

    [
      stalled_run_metrics(
        stalled_run_threshold_seconds,
        run_queue_metrics_period_seconds
      ),
      run_performance_metrics(
        run_performance_age_seconds,
        run_queue_metrics_period_seconds
      )
    ]
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
      ]
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
      {__MODULE__, :run_queue_metrics, [run_age_seconds]},
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
        )
      ]
    )
  end

  def run_queue_metrics(run_age_seconds) do
    if pid = Process.whereis(Repo) do
      check_repo_state(pid)

      trigger_run_claim_duration(run_age_seconds)
      trigger_available_runs_count()
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

    query =
      from a in Run,
        where: a.state == :available,
        or_where: a.state != :available and a.inserted_at > ^threshold_time

    query
    |> Repo.all()
    |> Enum.reduce({0, 0}, fn run, {sum, count} ->
      {sum + claim_duration(run, reference_time), count + 1}
    end)
    |> average()
  end

  defp claim_duration(%Run{state: :available} = run, reference_time) do
    DateTime.diff(reference_time, run.inserted_at, :millisecond)
  end

  defp claim_duration(run, _reference_time) do
    DateTime.diff(run.claimed_at, run.inserted_at, :millisecond)
  end

  defp average({_sum, 0}) do
    0.0
  end

  defp average({sum, count}) do
    (sum / count) |> Float.round(0)
  end

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
end
