defmodule Lightning.Janitor do
  @moduledoc """
  The Janitor is responsible for detecting runs that have been "lost" due to
  communication issues with the worker.

  Every X minutes the Janitor will check to ensure that no runs have been
  running for more than Y seconds.

  Configure your maximum run runtime with a WORKER_MAX_RUN_DURATION_SECONDS environment
  variable; the grace period will be an additional 20%.
  """

  use Oban.Worker,
    queue: :background,
    priority: 1,
    max_attempts: 10,
    unique: [period: 55]

  alias Lightning.Repo
  alias Lightning.Runs

  require Logger

  @doc """
  The perform function takes an `%Oban.Job`, allowing this module to be invoked
  by the Oban cron plugin.
  """
  @impl Oban.Worker
  def perform(%Oban.Job{}), do: find_and_update_lost()

  @doc """
  The find_and_update_lost function determines the current time, finds all
  runs that were claimed before the earliest allowable claim time for
  unfinished runs, and marks them as lost.
  """
  def find_and_update_lost do
    stream =
      Runs.Query.lost()
      |> Repo.stream()

    Repo.transaction(fn ->
      stream
      |> Stream.each(fn run ->
        case Runs.mark_run_lost(run) do
          {:ok, _updated_run} ->
            run
            |> Repo.preload([:log_lines, work_order: [:workflow]])
            |> Lightning.FailureAlerter.alert_on_failure()

          {:error, :already_completed} ->
            Logger.error(
              "Janitor Unexpected: Run #{run.id} already completed despite row lock"
            )

            :ok

          {:error, reason} ->
            Logger.error(
              "Janitor Unexpected: Run #{run.id} could not be marked as lost for #{inspect(reason)}"
            )

            :ok
        end
      end)
      |> Stream.run()

      # Note that this is a safety net which marks individual steps in a finished
      # run as lost if we have no data on them.
      Runs.Query.lost_steps() |> Runs.mark_steps_lost()
    end)
  end
end
