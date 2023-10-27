defmodule Lightning.Attempts.Query do
  @moduledoc """
  Query functions for working with Attempts
  """
  import Ecto.Query

  alias Lightning.Attempt

  @doc """
  Runs for a specific user
  """
  @spec lost(DateTime.t()) :: Ecto.Queryable.t()
  def lost(%DateTime{} = now) do
    grace_period =
      Application.get_env(:lightning, :max_run_duration)
      |> Kernel.*(0.2)
      |> trunc()

    earliest_acceptable_start = DateTime.add(now, grace_period)

    from(att in Attempt,
      where: is_nil(att.finished_at),
      where: att.claimed_at < ^earliest_acceptable_start
    )
  end
end
