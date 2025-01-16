defmodule LightningWeb.API.StepJSON do
  @moduledoc false

  def render("index.json", %{page: page}) do
    page.entries
    |> Enum.map(&process_instance/1)
  end

  def render("show.json", %{step: step}) do
    process_instance(step)
  end

  defp process_instance(step) do
    %{
      id: step.id,
      processRef: "#{step.job.name}:1:#{step.job.id}",
      initTime: step.started_at,
      state: step_state(step),
      lastChangeTime: step.updated_at
    }
  end

  defp step_state(step) do
    case {step.started_at, step.finished_at, step.exit_reason} do
      {nil, nil, _reason} ->
        "Ready"

      {_started_at, _finished_at, failed} when failed in ["cancel", "kill"] ->
        "Terminated"

      {_started_at, nil, _reason} ->
        "Active"

      {_started_at, _finished_at, "sucess"} ->
        "Completed"

      {_started_at, _finished_at, _reason} ->
        "Failed"
    end
  end
end
