defmodule Lightning.ObanManager do
  @moduledoc """
  The Oban Manager
  """
  require Logger

  def handle_event([:oban, :job, :exception], measure, meta, _pid) do
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
end
