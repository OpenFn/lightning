defmodule Lightning.Attempts.PromExPlugin do
  use PromEx.Plugin

  import Ecto.Query

  alias Lightning.Attempt
  alias Lightning.Repo

  @average_claim_event [:lightning, :attempt, :queue, :claim]
  @stalled_event [:lightning, :attempt, :queue, :stalled]

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

  @impl true
  def polling_metrics(opts) do
    {:ok, stalled_attempt_threshold_seconds} =
      opts |> Keyword.fetch(:stalled_attempt_threshold_seconds)

    {:ok, attempt_performance_age_seconds} =
      opts |> Keyword.fetch(:attempt_performance_age_seconds)

    [
      stalled_attempt_metrics(stalled_attempt_threshold_seconds),
      attempt_performance_metrics(attempt_performance_age_seconds)
    ]
  end

  defp stalled_attempt_metrics(threshold_seconds) do
    Polling.build(
      :lightning_stalled_attempt_metrics,
      5000,
      {__MODULE__, :stalled_attempt_count, [threshold_seconds]},
      [
        last_value(
          [:lightning, :attempt, :queue, :stalled, :count],
          event_name: @stalled_event,
          description: "The count of attempts stuck in the `available` state",
          measurement: :count
        )
      ]
    )
  end

  def stalled_attempt_count(threshold_seconds) do
    trigger_stalled_attempt_metric(Process.whereis(Repo), threshold_seconds)
  end

  defp trigger_stalled_attempt_metric(nil, _threshold_seconds) do
    nil
  end

  defp trigger_stalled_attempt_metric(repo_pid, threshold_seconds) do
    check_repo_state(repo_pid)

    threshold_time =
      DateTime.utc_now()
      |> DateTime.add(-1 * threshold_seconds)

    query =
      from a in Attempt,
        select: count(a.id),
        where: a.state == :available,
        where: a.inserted_at < ^threshold_time

    count = Repo.one(query)

    :telemetry.execute(@stalled_event, %{count: count}, %{})
  end

  defp attempt_performance_metrics(attempt_age_seconds) do
    Polling.build(
      :lightning_attempt_queue_metrics,
      5000,
      {__MODULE__, :attempt_claim_duration, [attempt_age_seconds]},
      [
        last_value(
          [
            :lightning,
            :attempt,
            :queue,
            :claim,
            :average_duration,
            :milliseconds
          ],
          event_name: @average_claim_event,
          description: "The average time taken before an attempt is claimed",
          measurement: :average_duration,
          unit: :millisecond
        )
      ]
    )
  end

  def attempt_claim_duration(attempt_age_seconds) do
    trigger_attempt_claim_duration(Process.whereis(Repo), attempt_age_seconds)
  end

  defp trigger_attempt_claim_duration(nil, _attempt_age_seconds) do
    nil
  end

  defp trigger_attempt_claim_duration(repo_pid, attempt_age_seconds) do
    check_repo_state(repo_pid)

    average_duration =
      calculate_average_claim_duration(DateTime.utc_now(), attempt_age_seconds)

    :telemetry.execute(
      @average_claim_event,
      %{average_duration: average_duration},
      %{}
    )
  end

  def calculate_average_claim_duration(reference_time, attempt_age_seconds) do
    threshold_time = reference_time |> DateTime.add(-attempt_age_seconds)

    query =
      from a in Attempt,
        where: a.state == :available,
        or_where: a.state != :available and a.inserted_at > ^threshold_time

    query
    |> Repo.all()
    |> Enum.reduce({0, 0}, fn attempt, {sum, count} ->
      {sum + claim_duration(attempt, reference_time), count + 1}
    end)
    |> average()
  end

  defp claim_duration(%Attempt{state: :available} = attempt, reference_time) do
    DateTime.diff(reference_time, attempt.inserted_at, :millisecond)
  end

  defp claim_duration(attempt, _reference_time) do
    DateTime.diff(attempt.claimed_at, attempt.inserted_at, :millisecond)
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
