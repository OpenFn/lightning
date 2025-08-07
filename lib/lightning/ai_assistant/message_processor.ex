defmodule Lightning.AiAssistant.MessageProcessor do
  @moduledoc """
  Asynchronous message processor for AI Assistant using Oban.

  This module handles the background processing of AI chat messages, ensuring
  reliable and scalable AI interactions. It processes messages outside of the
  web request lifecycle, providing better user experience and system resilience.
  """
  use Oban.Worker,
    queue: :ai_assistant,
    max_attempts: 1

  alias Lightning.AiAssistant
  alias Lightning.AiAssistant.ChatMessage
  alias Lightning.AiAssistant.ChatSession
  alias Lightning.Repo

  require Logger

  @timeout_buffer_percentage 10
  @minimum_buffer_ms 1000

  @doc """
  Processes an AI assistant message asynchronously.

  This is the main entry point called by Oban. It handles the complete
  lifecycle of message processing including status updates and broadcasting.

  ## Arguments

  - `job` - Oban job containing `message_id` and `session_id` in args

  ## Returns

  Always returns `:ok` to prevent Oban retries, even on errors.
  Errors are handled by updating message status and logging.
  """
  @impl Oban.Worker
  @spec perform(Oban.Job.t()) :: :ok
  def perform(%Oban.Job{args: %{"message_id" => message_id}}) do
    Logger.info("[MessageProcessor] Processing message: #{message_id}")

    case process_message(message_id) do
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

  @doc """
  Defines the job timeout based on Apollo configuration.

  Adds a 10-second buffer to the Apollo timeout to account for
  network overhead and processing time.

  ## Returns

  Timeout in milliseconds
  """
  @impl Oban.Worker
  @spec timeout(Oban.Job.t()) :: pos_integer()
  def timeout(_job) do
    apollo_timeout_ms = Lightning.Config.apollo(:timeout)
    buffer_ms = round(apollo_timeout_ms * @timeout_buffer_percentage / 100)
    apollo_timeout_ms + max(buffer_ms, @minimum_buffer_ms)
  end

  @doc false
  @spec process_message(String.t()) ::
          {:ok, AiAssistant.ChatSession.t()} | {:error, String.t()}
  defp process_message(message_id) do
    {:ok, session, message} =
      ChatMessage
      |> Repo.get!(message_id)
      |> update_message_status(:processing)

    result =
      case session.session_type do
        "job_code" ->
          process_job_message(session, message)

        "workflow_template" ->
          process_workflow_message(session, message)
      end

    case result do
      {:ok, _} ->
        {:ok, updated_session, _updated_message} =
          update_message_status(message, :success)

        {:ok, updated_session}

      {:error, error_message} ->
        {:ok, _updated_session, _updated_message} =
          update_message_status(message, :error)

        {:error, error_message}
    end
  end

  @doc false
  @spec process_job_message(AiAssistant.ChatSession.t(), ChatMessage.t()) ::
          {:ok, AiAssistant.ChatSession.t()} | {:error, String.t()}
  defp process_job_message(session, message) do
    enriched_session = AiAssistant.enrich_session_with_job_context(session)

    options =
      case session.meta do
        %{"message_options" => opts} when is_map(opts) ->
          Enum.map(opts, fn {k, v} -> {String.to_atom(k), v} end)

        _ ->
          []
      end

    AiAssistant.query(enriched_session, message.content, options)
  end

  @doc false
  @spec process_workflow_message(AiAssistant.ChatSession.t(), ChatMessage.t()) ::
          {:ok, AiAssistant.ChatSession.t()} | {:error, String.t()}
  defp process_workflow_message(session, message) do
    code = message.code || workflow_code_from_session(session)
    AiAssistant.query_workflow(session, message.content, code: code)
  end

  @doc false
  @spec broadcast_status(
          String.t(),
          atom() | {atom(), AiAssistant.ChatSession.t()}
        ) :: :ok
  defp broadcast_status(session_id, status) do
    Lightning.broadcast(
      "ai_session:#{session_id}",
      {:ai_assistant, :message_status_changed,
       %{
         status: status,
         session_id: session_id
       }}
    )
  end

  @doc """
  Updates a message's status and broadcasts the change.

  This function updates the message status in the database, fetches the updated
  session with all associations, and broadcasts the status change to connected
  clients via Phoenix PubSub.

  ## Parameters

    - `message` - The `ChatMessage` struct to update
    - `status` - The new status atom (`:processing`, `:success`, or `:error`)

  ## Returns

    `{:ok, updated_session, updated_message}` - Tuple with the updated session
    and message structs
  """
  @spec update_message_status(
          ChatMessage.t(),
          atom()
        ) ::
          {:ok, ChatSession.t(), ChatMessage.t()}
  def update_message_status(message, status) do
    changes = build_status_changes(status)

    updated_message =
      message
      |> Ecto.Changeset.change(changes)
      |> Repo.update!()

    updated_session = AiAssistant.get_session!(updated_message.chat_session_id)

    broadcast_status(updated_session.id, {status, updated_session})

    {:ok, updated_session, updated_message}
  end

  @doc false
  @spec build_status_changes(atom()) :: map()
  defp build_status_changes(:processing) do
    %{
      status: :processing,
      processing_started_at: DateTime.utc_now()
    }
  end

  defp build_status_changes(:success) do
    %{
      status: :success,
      processing_completed_at: DateTime.utc_now()
    }
  end

  defp build_status_changes(:error) do
    %{
      status: :error,
      processing_completed_at: DateTime.utc_now()
    }
  end

  @doc false
  @spec workflow_code_from_session(AiAssistant.ChatSession.t()) ::
          String.t() | nil
  defp workflow_code_from_session(session) do
    session.messages
    |> Enum.reverse()
    |> Enum.find_value(nil, fn
      %{role: :assistant, code: code} when not is_nil(code) -> code
      _ -> nil
    end)
  end
end
