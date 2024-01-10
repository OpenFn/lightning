defmodule Lightning.Attempts.PromExPlugin do
  use PromEx.Plugin

  alias Lightning.Attempt
  alias Lightning.Repo
  import Ecto.Query

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

    [
      stalled_attempt_metrics(stalled_attempt_threshold_seconds)
    ]
  end

  defp stalled_attempt_metrics(threshold_seconds) do
    Polling.build(
      :lightning_attempt_polling_events,
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
    # NOTE: During local testing of server starts, having the pid was not enough
    # a call to .get_state was also required, otherwise the metric triggers before
    # the Repo GenServer is available.
    #
    :sys.get_state(repo_pid)

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
end
