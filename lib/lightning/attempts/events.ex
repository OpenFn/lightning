defmodule Lightning.Attempts.Events do
  defmodule RunStarted do
    @moduledoc false
    defstruct run: nil
  end

  defmodule RunCompleted do
    @moduledoc false
    defstruct run: nil
  end

  defmodule AttemptUpdated do
    @moduledoc false
    defstruct attempt: nil
  end

  defmodule LogAppended do
    @moduledoc false
    defstruct log_line: nil
  end

  def run_started(attempt_id, run) do
    Lightning.broadcast(
      topic(attempt_id),
      %RunStarted{run: run}
    )
  end

  def run_completed(attempt_id, run) do
    Lightning.broadcast(
      topic(attempt_id),
      %RunCompleted{run: run}
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
