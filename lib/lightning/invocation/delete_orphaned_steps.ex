defmodule Lightning.Invocation.DeleteOrphanedSteps do
  @moduledoc """
  Deletes steps that no run links to.

  Steps are always written together with their `run_steps` row, so a step
  without one can't be reached from any run or work order. History retention
  used to leave them behind, and they stop a deleted workflow from being
  purged because `steps.snapshot_id` restricts deleting the snapshot.

  Rerunning it is safe: it just finds whatever is left. It runs on the
  `maintenance` queue, which only versions that have this module poll, so a
  node still running an older release never picks it up mid-deploy.
  """

  use Oban.Worker,
    queue: :maintenance,
    max_attempts: 5,
    unique: [
      period: :infinity,
      states: [:available, :scheduled, :executing, :retryable]
    ]

  import Ecto.Query

  alias Lightning.Config
  alias Lightning.Invocation.Step
  alias Lightning.Repo
  alias Lightning.RunStep

  require Logger

  # Each deleted step cascades into every log_lines partition, which costs
  # about 100ms per step on a cold cache, so batches stay small to keep each
  # statement short.
  @batch_size 100

  @impl Oban.Worker
  def perform(%Oban.Job{}) do
    timeout = Config.default_ecto_database_timeout() * 6

    ids = Repo.all(select(orphaned_steps(), [s], s.id), timeout: timeout)

    deleted =
      ids
      |> Enum.chunk_every(@batch_size)
      |> Enum.reduce(0, fn batch, total ->
        {count, _} =
          Repo.delete_all(where(orphaned_steps(), [s], s.id in ^batch),
            timeout: timeout
          )

        total + count
      end)

    Logger.info("Deleted #{deleted} steps that no run links to")

    :ok
  end

  defp orphaned_steps do
    from(s in Step,
      as: :step,
      where:
        not exists(
          from(rs in RunStep,
            where: rs.step_id == parent_as(:step).id,
            select: 1
          )
        )
    )
  end
end
