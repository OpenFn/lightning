defmodule Lightning.Attempts.Query do
  @moduledoc """
  Query functions for working with Attempts
  """
  import Ecto.Query

  require Lightning.Attempt
  alias Lightning.Attempt

  @doc """
  Runs for a specific user
  """
  @spec lost(DateTime.t()) :: Ecto.Queryable.t()
  def lost(%DateTime{} = now) do
    grace_period = Lightning.Config.grace_period()
    earliest_acceptable_start = DateTime.add(now, grace_period)

    final_states = Attempt.final_states()

    from(att in Attempt,
      where: is_nil(att.finished_at),
      where: att.state not in ^final_states,
      where: att.claimed_at < ^earliest_acceptable_start
    )
  end
end
