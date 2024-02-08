defmodule Lightning.Runs.Events do
  defmodule StepStarted do
    @moduledoc false
    defstruct step: nil
  end

  defmodule StepCompleted do
    @moduledoc false
    defstruct step: nil
  end

  defmodule RunUpdated do
    @moduledoc false
    defstruct run: nil
  end

  defmodule LogAppended do
    @moduledoc false
    defstruct log_line: nil
  end

  defmodule DataclipUpdated do
    @moduledoc false
    defstruct dataclip: nil
  end

  def step_started(run_id, step) do
    Lightning.broadcast(
      topic(run_id),
      %StepStarted{step: step}
    )
  end

  def step_completed(run_id, step) do
    Lightning.broadcast(
      topic(run_id),
      %StepCompleted{step: step}
    )
  end

  def run_updated(run) do
    Lightning.broadcast(
      topic(run.id),
      %RunUpdated{run: run}
    )
  end

  def log_appended(log_line) do
    Lightning.broadcast(
      topic(log_line.run_id),
      %LogAppended{log_line: log_line}
    )
  end

  def dataclip_updated(run_id, dataclip) do
    Lightning.broadcast(
      topic(run_id),
      %DataclipUpdated{dataclip: dataclip}
    )
  end

  def subscribe(%Lightning.Run{id: id}) do
    Lightning.subscribe(topic(id))
  end

  defp topic(id), do: "run_events:#{id}"
end
