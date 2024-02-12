defmodule Lightning.Runs.Query do
  @moduledoc """
  Query functions for working with Runs
  """
  import Ecto.Query

  alias Lightning.Run

  require Lightning.Run

  @doc """
  Return all runs that have been claimed by a worker before the earliest
  acceptable start time (determined by the longest acceptable run time) but are
  still incomplete. This indicates that we may have lost contact with the worker
  that was responsible for executing the run.
  """
  @spec lost(DateTime.t()) :: Ecto.Queryable.t()
  def lost(%DateTime{} = now) do
    max_run_duration_seconds =
      Application.get_env(:lightning, :max_run_duration_seconds)

    grace_period = Lightning.Config.grace_period()

    oldest_valid_claim =
      now
      |> DateTime.add(-max_run_duration_seconds, :second)
      |> DateTime.add(-grace_period, :second)

    final_states = Run.final_states()

    from(att in Run,
      where: is_nil(att.finished_at),
      where: att.state not in ^final_states,
      where: att.claimed_at < ^oldest_valid_claim
    )
  end
end
