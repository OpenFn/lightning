defmodule Lightning.AiAssistant.MessageProcessor do
  @moduledoc """
  Processes AI assistant messages asynchronously using Oban.
  """
  use Oban.Worker,
    queue: :ai_assistant,
    max_attempts: 1

  alias Lightning.AiAssistant
  alias Lightning.AiAssistant.ChatMessage
  alias Lightning.Repo

  require Logger

  @impl Oban.Worker
  def perform(%Oban.Job{
        args: %{"message_id" => message_id, "session_id" => session_id}
      }) do
    Logger.info("[MessageProcessor] Processing message: #{message_id}")

    message = Repo.get!(ChatMessage, message_id)
    session = AiAssistant.get_session!(session_id)

    # Mark as processing
    {:ok, _} =
      message
      |> Ecto.Changeset.change(%{
        status: :processing,
        processing_started_at: DateTime.utc_now()
      })
      |> Repo.update()

    # Broadcast processing status
    broadcast_status(session_id, :processing)

    # Process based on session type
    result = process_message(session, message)

    # Always return :ok so Oban doesn't retry
    case result do
      {:ok, _updated_session} ->
        Logger.info(
          "[MessageProcessor] Successfully processed message: #{message_id}"
        )

        :ok

      {:error, reason} ->
        Logger.error(
          "[MessageProcessor] Failed to process message: #{message_id}, reason: #{inspect(reason)}"
        )

        :ok
    end
  end

  @impl Oban.Worker
  def timeout(_job) do
    apollo_timeout_ms = Lightning.Config.apollo(:timeout) || 30_000
    apollo_timeout_ms + 10_000
  end

  defp process_message(session, message) do
    result =
      case session.session_type do
        "job_code" ->
          process_job_message(session, message)

        "workflow_template" ->
          process_workflow_message(session, message)
      end

    case result do
      {:ok, updated_session} ->
        # Mark message as complete
        {:ok, _} =
          message
          |> Ecto.Changeset.change(%{
            status: :success,
            completed_at: DateTime.utc_now()
          })
          |> Repo.update()

        broadcast_status(session.id, {:completed, updated_session})
        {:ok, updated_session}

      {:error, error_message} ->
        # Mark message as failed
        {:ok, _} =
          message
          |> Ecto.Changeset.change(%{
            status: :error,
            completed_at: DateTime.utc_now()
          })
          |> Repo.update()

        broadcast_status(session.id, :error)
        {:error, error_message}
    end
  end

  defp process_job_message(session, message) do
    job = Repo.get!(Lightning.Workflows.Job, session.job_id)

    session =
      AiAssistant.put_expression_and_adaptor(
        session,
        job.body,
        job.adaptor
      )

    session =
      if run_id = session.meta["follow_run_id"] do
        logs = Lightning.Invocation.assemble_logs_for_job_and_run(job.id, run_id)
        %{session | logs: logs}
      else
        session
      end

    AiAssistant.query(session, message.content, processing_message: message)
  end

  defp process_workflow_message(session, message) do
    workflow_code =
      message.workflow_code || AiAssistant.get_latest_workflow_yaml(session)

    AiAssistant.query_workflow(session, message.content,
      workflow_code: workflow_code,
      processing_message: message
    )
  end

  @doc false
  defp broadcast_status(session_id, status) do
    Lightning.broadcast(
      "ai_session:#{session_id}",
      {:ai_assistant, :message_status_changed, status}
    )
  end
end
