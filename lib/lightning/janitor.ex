defmodule Lightning.Janitor do
  @moduledoc """
  The Janitor is responsible for detecting attempts that have been "lost" due to
  communication issues with the worker.

  Every X minutes the Janitor will check to ensure that no attempts have been
  running for more than Y seconds.

  Configure your maximum attempt runtime with a WORKER_MAX_RUN_DURATION_SECONDS environment
  variable; the grace period will be an additional 20%.
  """

  use Oban.Worker,
    queue: :background,
    priority: 1,
    max_attempts: 10,
    unique: [period: 55]

  alias Lightning.Attempts
  alias Lightning.Repo

  @doc """
  The perform function takes an `%Oban.Job`, allowing this module to be invoked
  by the Oban cron plugin.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{}), do: find_and_update_lost()

  @doc """
  The find_and_update_lost function determines the current time, finds all
  attempts that were claimed before the earliest allowable claim time for
  unfinished attempts, and marks them as lost.
  """
  def find_and_update_lost do
    now = DateTime.utc_now()

    Attempts.Query.lost(now)
    |> Repo.all()
    |> Enum.each(fn att ->
      Attempts.mark_attempt_lost(att)
    end)
  end
end
