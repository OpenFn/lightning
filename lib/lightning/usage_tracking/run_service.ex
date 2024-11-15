defmodule Lightning.UsageTracking.RunService do
  @moduledoc """
  Supports the generation of metrics related to runs and steps.


  """
  def finished_steps(run, date) do
    run.steps
    |> finished_on(date)
  end

  def unique_job_ids(steps, date) do
    steps
    |> finished_on(date)
    |> Enum.map(& &1.job_id)
    |> Enum.uniq_by(& &1)
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
