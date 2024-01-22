defmodule Lightning.Attempts.Events do
  defmodule StepStarted do
    @moduledoc false
    defstruct step: nil
  end

  defmodule StepCompleted do
    @moduledoc false
    defstruct step: nil
  end

  defmodule AttemptUpdated do
    @moduledoc false
    defstruct attempt: nil
  end

  defmodule LogAppended do
    @moduledoc false
    defstruct log_line: nil
  end

  def step_started(attempt_id, step) do
    Lightning.broadcast(
      topic(attempt_id),
      %StepStarted{step: step}
    )
  end

  def step_completed(attempt_id, step) do
    Lightning.broadcast(
      topic(attempt_id),
      %StepCompleted{step: step}
    )
  end

  def attempt_updated(attempt) do
    Lightning.broadcast(
      topic(attempt.id),
      %AttemptUpdated{attempt: attempt}
    )
  end

  def log_appended(log_line) do
    Lightning.broadcast(
      topic(log_line.attempt_id),
      %LogAppended{log_line: log_line}
    )
  end

  def subscribe(%Lightning.Attempt{id: id}) do
    Lightning.subscribe(topic(id))
  end

  defp topic(id), do: "attempt_events:#{id}"
end
