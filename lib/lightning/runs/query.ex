defmodule Lightning.Runs.Query do
  @moduledoc """
  Query functions for working with Runs
  """
  import Ecto.Query

  alias Lightning.Run

  require Lightning.Run

  @doc """
  Return all runs that have been claimed by a worker before the earliest
  acceptable start time (determined by the run options and grace period) but are
  still incomplete. This indicates that we may have lost contact with the worker
  that was responsible for executing the run.
  """
  @spec lost :: Ecto.Queryable.t()
  def lost do
    now = Lightning.current_time()

    grace_period_ms = Lightning.Config.grace_period() * 1000

    # TODO: Remove after live deployment rollouts are done. ====================
    fallback_max = Lightning.Config.default_max_run_duration()

    fallback_oldest_claim =
      now
      |> DateTime.add(-fallback_max, :second)
      |> DateTime.add(-grace_period_ms, :millisecond)

    # ==========================================================================

    final_states = Run.final_states()

    from(r in Run,
      where: is_nil(r.finished_at),
      where: r.state not in ^final_states,
      where:
        fragment(
          "? + ((? ->> 'run_timeout_ms')::int + ?) * '1 millisecond'::interval < ?",
          r.claimed_at,
          r.options,
          ^grace_period_ms,
          ^now
        ) or (is_nil(r.options) and r.claimed_at < ^fallback_oldest_claim)
    )
  end
end
