defmodule Lightning.ObanManager do
  @moduledoc """
  The Oban Manager
  """
  require Logger

  alias Lightning.Repo
  alias Lightning.AttemptRun
  alias Lightning.Invocation

  @doc """
  handles oban events
  """
  def handle_event([:oban, :circuit, :open], _measure, meta, _pid),
    do: Logger.info("Circuit open #{inspect(meta, pretty: true)}")

  def handle_event([:oban, :circuit, :trip], _measure, meta, _pid) do
    Logger.error("Circuit tripped with #{inspect(meta, pretty: true)}")

    context = Map.take(meta, [:name])

    Sentry.capture_exception(meta.error,
      stacktrace: meta.stacktrace,
      message: meta.message,
      extra: context,
      tags: %{type: "oban"}
    )
  end

  def handle_event([:oban, :job, :exception], measure, meta, _pid) do
    if meta.job.worker == "Lightning.Pipeline" and
         Map.has_key?(meta.job.args, "attempt_run_id") do
      update_run(Map.get(meta.job.args, "attempt_run_id"))
    end

    Logger.error(~s"""
    Oban exception:
    #{inspect(meta.error)}
    #{Exception.format_stacktrace(meta.stacktrace)}
    meta:
      #{Map.drop(meta, [:error, :stacktrace]) |> inspect(pretty: true)}
    (#{inspect(measure, pretty: true)})
    """)

    context =
      meta.job
      |> Map.take([:id, :args, :queue, :worker])
      |> Map.merge(measure)

    error = meta.error
    timeout? = Map.get(error, :reason) == :timeout

    if timeout? do
      Sentry.capture_message("Processor Timeout",
        level: "warning",
        message: error,
        extra: context,
        tags: %{type: "timeout"}
      )
    else
      Sentry.capture_exception(error,
        stacktrace: meta.stacktrace,
        message: error,
        error: error,
        extra: context,
        tags: %{type: "oban"}
      )
    end
  end

  defp update_run(attempt_run_id),
    do:
      Repo.get!(AttemptRun, attempt_run_id)
      |> Ecto.assoc(:run)
      |> Repo.one!()
      |> Invocation.update_run(%{
        finished_at: DateTime.utc_now()
      })
end
