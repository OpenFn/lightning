defmodule Lightning.ObanManager do
  @moduledoc """
  The Oban Manager
  """
  alias Lightning.AiAssistant.MessageProcessor

  require Logger

  def handle_event(
        [:oban, :job, :exception],
        measure,
        %{job: %{queue: "ai_assistant"}} = meta,
        _pid
      ) do
    MessageProcessor.handle_ai_assistant_exception(measure, meta)
  end

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
      Lightning.Sentry.capture_message("Processor Timeout",
        level: :warning,
        extra: Map.merge(context, %{exception: inspect(error)}),
        tags: %{type: "timeout"}
      )
    else
      Lightning.Sentry.capture_exception(error,
        stacktrace: meta.stacktrace,
        extra: context,
        tags: %{type: "oban"}
      )
    end
  end

  def handle_event(
        [:oban, :job, :stop],
        measure,
        %{job: %{queue: "ai_assistant"}} = meta,
        _pid
      ) do
    MessageProcessor.handle_ai_assistant_stop(measure, meta)
  end

  def handle_event([:oban, :job, :stop], _measure, _meta, _pid), do: :ok
end
