defmodule Lightning.UsageTracking.RunService do
  @moduledoc """
  Supports the generation of metrics related to runs and steps.


  """
  def unique_jobs(steps, date) do
    steps
    |> finished_on(date)
    |> Enum.map(& &1.job)
    |> Enum.uniq_by(& &1.id)
  end

  defp finished_on(collection, date) do
    collection
    |> Enum.filter(fn
      %{finished_at: nil} ->
        false

      %{finished_at: finished_at} ->
        finished_at |> DateTime.to_date() == date
    end)
  end
end
