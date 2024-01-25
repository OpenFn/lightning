defmodule Lightning.Attempts.Query do
  @moduledoc """
  Query functions for working with Attempts
  """
  import Ecto.Query

  alias Lightning.Attempt

  require Lightning.Attempt

  @doc """
  Return all attempts that have been claimed by a worker before the earliest
  acceptable start time (determined by the longest acceptable run time) but are
  still incomplete. This indicates that we may have lost contact with the worker
  that was responsible for executing the attempt.
  """
  @spec lost(DateTime.t()) :: Ecto.Queryable.t()
  def lost(%DateTime{} = now) do
    max_run_duration = Application.get_env(:lightning, :max_run_duration_seconds)
    grace_period = Lightning.Config.grace_period()

    oldest_valid_claim =
      now
      |> DateTime.add(-max_run_duration, :second)
      |> DateTime.add(-grace_period, :second)

    final_states = Attempt.final_states()

    from(att in Attempt,
      where: is_nil(att.finished_at),
      where: att.state not in ^final_states,
      where: att.claimed_at < ^oldest_valid_claim
    )
  end
end
