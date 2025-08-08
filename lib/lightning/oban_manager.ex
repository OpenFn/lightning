defmodule Lightning.ObanManager do
  @moduledoc """
  The Oban Manager
  """
  alias Lightning.AiAssistant.ChatMessage
  alias Lightning.AiAssistant.MessageProcessor
  alias Lightning.Repo

  require Logger

  def handle_event(
        [:oban, :job, :exception],
        measure,
        %{job: %{queue: "ai_assistant"}} = meta,
        _pid
      ) do
    handle_ai_assistant_exception(measure, meta)
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
    handle_ai_assistant_stop(measure, meta)
  end

  def handle_event([:oban, :job, :stop], _measure, _meta, _pid), do: :ok

  defp handle_ai_assistant_exception(measure, meta) do
    job = meta.job
    error = meta.error
    timeout? = Map.get(error, :reason) == :timeout

    Logger.error(~s"""
    AI Assistant exception:
    Worker: #{job.worker}
    Type: #{if timeout?, do: "Timeout", else: "Error"}
    Args: #{inspect(job.args)}
    Error: #{inspect(error)}
    Duration: #{measure.duration / 1_000_000}ms
    """)

    ChatMessage
    |> Repo.get!(job.args["message_id"])
    |> case do
      %ChatMessage{id: message_id, status: status} = message
      when status in [:pending, :processing] ->
        Logger.info(
          "[AI Assistant] Updating message #{message_id} to error status after exception"
        )

        {:ok, _updated_session, _updated_message} =
          MessageProcessor.update_message_status(message, :error)

      %ChatMessage{id: message_id, status: status} ->
        Logger.debug(
          "[AI Assistant] Message #{message_id} already has status: #{status}, skipping cleanup"
        )
    end

    context = %{
      worker: job.worker,
      args: job.args,
      queue: job.queue,
      job_id: job.id,
      duration_ms: measure.duration / 1_000_000,
      memory: measure.memory,
      reductions: measure.reductions
    }

    if timeout? do
      Lightning.Sentry.capture_message("AI Assistant Timeout: #{job.worker}",
        level: :warning,
        extra: Map.merge(context, %{error: inspect(error)}),
        tags: %{
          type: "ai_timeout",
          queue: "ai_assistant",
          worker: job.worker
        }
      )
    else
      Lightning.Sentry.capture_exception(error,
        stacktrace: meta.stacktrace,
        extra: context,
        tags: %{
          type: "ai_error",
          queue: "ai_assistant",
          worker: job.worker
        }
      )
    end
  end

  defp handle_ai_assistant_stop(measure, meta) do
    case meta.state do
      :success ->
        :ok

      other ->
        Logger.error("""
        AI Assistant stop (non-success):
        Worker: #{meta.job.worker}
        State: #{inspect(other)}
        Args: #{inspect(meta.job.args)}
        Duration: #{measure.duration / 1_000_000}ms
        """)

        ChatMessage
        |> Repo.get!(meta.job.args["message_id"])
        |> case do
          %ChatMessage{id: message_id, status: status} = message
          when status in [:pending, :processing] ->
            Logger.info(
              "[AI Assistant] Updating message #{message_id} to error status after stop=#{other}"
            )

            {:ok, _sess, _msg} =
              MessageProcessor.update_message_status(message, :error)

          _ ->
            :ok
        end

        Lightning.Sentry.capture_message(
          "AI Assistant Stop (#{other}): #{meta.job.worker}",
          level: :warning,
          extra: %{
            worker: meta.job.worker,
            args: meta.job.args,
            job_id: meta.job.id,
            queue: meta.job.queue,
            state: other,
            duration_ms: measure.duration / 1_000_000,
            memory: measure.memory,
            reductions: measure.reductions
          },
          tags: %{
            type: "ai_stop",
            queue: "ai_assistant",
            worker: meta.job.worker,
            state: other
          }
        )
    end
  end
end
