defmodule Lightning.Janitor do
  @moduledoc """
  The Janitor is responsible for detecting attempts that have been "lost" due to
  communication issues with the worker.

  Every X minutes the Janitor will check to ensure that no attempts have been
  running for more than Y seconds.

  Configure your maximum attempt runtime with a MAX_RUN_DURATION environment
  variable; the grace period will be an additional 20%.
  """

  use Oban.Worker,
    queue: :background,
    priority: 1,
    max_attempts: 10,
    unique: [period: 55]

  require Logger

  alias Lightning.Repo
  alias Lightning.Attempts

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
      error_type =
        case att.state do
          :claimed -> "LostAfterClaim"
          :started -> "LostAfterStart"
          _other -> "UnknownReason"
        end

      Logger.warning(fn ->
        "Detected lost attempt with reason #{error_type}: #{inspect(att)}"
      end)

      Attempts.complete_attempt(att, {:lost, error_type, nil})
      # TODO - Implement this in https://github.com/OpenFn/Lightning/issues/1348
      # Attempts.mark_unfinished_runs_lost(att)
    end)
  end
end
