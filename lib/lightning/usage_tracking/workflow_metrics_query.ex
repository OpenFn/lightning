defmodule Lightning.UsageTracking.WorkflowMetricsQuery do
  @moduledoc """
  Query module to support workflow metrics while allowing for fewer test
  permutations.


  """
  import Ecto.Query

  alias Lightning.Run

  def workflow_runs(%{id: workflow_id}) do
    from r in Run,
      join: w in assoc(r, :workflow),
      on: w.id == ^workflow_id
  end

  def runs_finished_on(query, date) do
    start_of_day = DateTime.new!(date, ~T[00:00:00])

    start_of_next_day =
      date
      |> Date.add(1)
      |> DateTime.new!(~T[00:00:00])

    from r in query,
      where: not is_nil(r.finished_at),
      where: r.finished_at >= ^start_of_day,
      where: r.finished_at < ^start_of_next_day
  end
end
