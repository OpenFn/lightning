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
    Logger.debug("[MessageProcessor] Processing message: #{message_id}")

    case process_message(message_id) do
      {:ok, _updated_session} ->
        Logger.debug(
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
    apollo_timeout_ms = Lightning.Config.apollo(:timeout) || 30_000
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
      {:ok, :streaming} ->
        # Streaming in progress, don't mark as success yet
        # The streaming_complete event will trigger success later
        {:ok, session}

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

    # Use streaming for job messages
    stream_job_message(enriched_session, message.content, options)
  end

  @doc false
  @spec stream_job_message(AiAssistant.ChatSession.t(), String.t(), keyword()) ::
          {:ok, :streaming | AiAssistant.ChatSession.t()} | {:error, String.t()}
  defp stream_job_message(session, content, options) do
    # For now, start streaming and use existing query as fallback
    try do
      start_streaming_request(session, content, options)
      # Return :streaming indicator - message stays in processing state
      {:ok, :streaming}
    rescue
      _ ->
        # Fallback to non-streaming if streaming fails
        AiAssistant.query(session, content, options)
    end
  end

  @doc false
  @spec start_streaming_request(
          AiAssistant.ChatSession.t(),
          String.t(),
          keyword()
        ) :: :ok
  defp start_streaming_request(session, content, options) do
    # Build payload for Apollo
    context = build_context(session, options)
    history = get_chat_history(session)

    payload = %{
      "api_key" => Lightning.Config.apollo(:ai_assistant_api_key),
      "content" => content,
      "context" => context,
      "history" => history,
      "meta" => session.meta || %{},
      "stream" => true
    }

    # Add session ID for Lightning broadcasts
    sse_payload = Map.put(payload, "lightning_session_id", session.id)

    # Start Apollo SSE stream
    apollo_url = get_apollo_url("job_chat")

    case Lightning.ApolloClient.SSEStream.start_stream(apollo_url, sse_payload) do
      {:ok, _pid} ->
        Logger.debug(
          "[MessageProcessor] Started Apollo SSE stream for session #{session.id}"
        )

      {:error, reason} ->
        Logger.error(
          "[MessageProcessor] Failed to start Apollo stream: #{inspect(reason)}"
        )

        Logger.debug("[MessageProcessor] Falling back to HTTP client")
        # Fall back to existing HTTP implementation
        raise "SSE stream failed, falling back to HTTP (not implemented yet)"
    end

    :ok
  end

  defp get_apollo_url(service) do
    base_url = Lightning.Config.apollo(:endpoint)
    "#{base_url}/services/#{service}/stream"
  end

  defp get_chat_history(session) do
    session.messages
    |> Enum.map(fn message ->
      %{
        "role" => to_string(message.role),
        "content" => message.content
      }
    end)
  end

  defp build_context(session, options) do
    # Start with session context (expression, adaptor, logs)
    base_context = %{
      expression: session.expression,
      adaptor: session.adaptor,
      log: session.logs
    }

    # Apply options to filter context (e.g., code: false removes expression)
    Enum.reduce(options, base_context, fn
      {:code, false}, acc ->
        Map.drop(acc, [:expression])

      {:logs, false}, acc ->
        Map.drop(acc, [:log])

      _opt, acc ->
        acc
    end)
  end

  @doc false
  @spec process_workflow_message(AiAssistant.ChatSession.t(), ChatMessage.t()) ::
          {:ok, AiAssistant.ChatSession.t()} | {:error, String.t()}
  defp process_workflow_message(session, message) do
    code = message.code || workflow_code_from_session(session)

    # Try streaming first, fall back to HTTP if it fails
    try do
      start_workflow_streaming_request(session, message.content, code)
      {:ok, :streaming}
    rescue
      _ ->
        # Fallback to non-streaming
        AiAssistant.query_workflow(session, message.content, code: code)
    end
  end

  @doc false
  @spec start_workflow_streaming_request(
          AiAssistant.ChatSession.t(),
          String.t(),
          String.t() | nil
        ) :: :ok
  defp start_workflow_streaming_request(session, content, code) do
    # Build payload for Apollo workflow_chat
    history = get_chat_history(session)

    payload =
      %{
        "api_key" => Lightning.Config.apollo(:ai_assistant_api_key),
        "content" => content,
        "existing_yaml" => code,
        "history" => history,
        "meta" => session.meta || %{},
        "stream" => true
      }
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Enum.into(%{})

    # Add session ID for Lightning broadcasts
    sse_payload = Map.put(payload, "lightning_session_id", session.id)

    # Start Apollo SSE stream for workflow_chat
    apollo_url = get_apollo_url("workflow_chat")

    case Lightning.ApolloClient.SSEStream.start_stream(apollo_url, sse_payload) do
      {:ok, _pid} ->
        Logger.debug(
          "[MessageProcessor] Started Apollo SSE stream for workflow session #{session.id}"
        )

      {:error, reason} ->
        Logger.error(
          "[MessageProcessor] Failed to start Apollo workflow stream: #{inspect(reason)}"
        )

        Logger.debug("[MessageProcessor] Falling back to HTTP client")
        raise "SSE stream failed, triggering fallback to HTTP"
    end

    :ok
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

  @doc """
  Handles exceptions for `ai_assistant` Oban jobs.

  ## Parameters
    * `measure` — A map containing job execution metrics (`duration`, `memory`, `reductions`).
    * `meta` — A map containing job metadata (`job`, `error`, `stacktrace`, etc.).
  """
  def handle_ai_assistant_exception(measure, meta) do
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
        Logger.debug(
          "[AI Assistant] Updating message #{message_id} to error status after exception"
        )

        {:ok, _updated_session, _updated_message} =
          update_message_status(message, :error)

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

  @doc """
  Handles `:stop` events for `ai_assistant` Oban jobs.

  This function is invoked when a job in the `ai_assistant` queue stops with a non-success state
  (e.g., `:discard`, `:cancelled`, or other custom stop reasons).

  Jobs with the `:success` state are ignored.

  ## Parameters
    * `measure` — A map containing job execution metrics (`duration`, `memory`, `reductions`).
    * `meta` — A map containing job metadata (`job`, `state`, etc.).
  """
  def handle_ai_assistant_stop(measure, meta) do
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
            Logger.debug(
              "[AI Assistant] Updating message #{message_id} to error status after stop=#{other}"
            )

            {:ok, _sess, _msg} = update_message_status(message, :error)

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
