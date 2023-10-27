defmodule Lightning.Janitor do
  @moduledoc """
  The Janitor is responsible for detecting attempts that have been "lost" due to
  communication issues with the worker.

  Every X minutes the Janitor will check to ensure that no attempts have been
  running for more than Y seconds.
  """

  use Oban.Worker,
    queue: :background,
    priority: 1,
    max_attempts: 10,
    unique: [period: 55]

  require Logger

  import Ecto.Query
  alias Lightning.{Repo, Attempt}

  @doc """
  Takes a type to either deletes completed Oban jobs, preserving
  discarded/cancelled for inspection or marks orphaned Oban jobs as cancelled,
  preserving them for inspection.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    now = DateTime.utc_now()
    grace_period = Application.get_env(:lightning, :max_run_duration) * -0.2
    earliest_acceptable_start = Timex.shift(now, seconds: grace_period)

    from(att in Attempt,
      where: is_nil(att.finished_at),
      # TODO: decide if this should be claimed_at or started_at
      where: att.claimed_at < ^earliest_acceptable_start
    )
    |> Repo.all()
    |> Enum.each(fn att ->
      Logger.error(fn -> "Detected :lost attempt: #{inspect(att)}" end)
      Attempt.complete(att, :lost)
    end)
  end
end
