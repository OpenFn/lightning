defmodule Lightning.UsageTracking.RunService do
  @moduledoc """
  Supports the generation of metrics related to runs and steps.


  """
  def finished_runs(all_runs, date) do
    all_runs
    |> finished_on(date)
  end

  def finished_steps(runs, date) do
    runs
    |> Enum.flat_map(& &1.steps)
    |> finished_on(date)
  end

  def unique_job_ids(steps, date) do
    steps
    |> finished_on(date)
    |> Enum.uniq_by(& &1.job_id)
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
