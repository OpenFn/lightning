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
            buckets: exponential!(100, 2, 10)
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

    [
      stalled_run_metrics(stalled_run_threshold_seconds),
      run_performance_metrics(run_performance_age_seconds)
    ]
  end

  defp stalled_run_metrics(threshold_seconds) do
    Polling.build(
      :lightning_stalled_run_metrics,
      5000,
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

  defp run_performance_metrics(run_age_seconds) do
    Polling.build(
      :lightning_run_queue_metrics,
      5000,
      {__MODULE__, :run_claim_duration, [run_age_seconds]},
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
        )
      ]
    )
  end

  def run_claim_duration(run_age_seconds) do
    trigger_run_claim_duration(Process.whereis(Repo), run_age_seconds)
  end

  defp trigger_run_claim_duration(nil, _run_age_seconds) do
    nil
  end

  defp trigger_run_claim_duration(repo_pid, run_age_seconds) do
    check_repo_state(repo_pid)

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
end
