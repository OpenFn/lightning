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
  alias Lightning.Invocation
  alias Lightning.Repo
  alias Lightning.Scrubber

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
    case process_message(message_id) do
      {:ok, _updated_session} ->
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

    is_job = !is_nil(message.job_id)
    # IO.inspect(%{message: message.job_id}, label: "han:ai")
    # instead of session_type we need to check whether the message has a job_id!
    result =
      if is_job do
        session = %{session | job_id: message.job_id}
        process_job_message(session, message)
      else
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

    # Add I/O data if requested
    options =
      case session.meta do
        %{"message_options" => %{"attach_io_data" => true, "step_id" => step_id}}
        when is_binary(step_id) ->
          {input, output} = fetch_and_scrub_io_data(step_id)

          options
          |> Keyword.put(:input, input)
          |> Keyword.put(:output, output)

        _ ->
          options
      end

    AiAssistant.query(enriched_session, message.content, options)
  end

  @spec fetch_and_scrub_io_data(String.t()) :: {map() | nil, map() | nil}
  defp fetch_and_scrub_io_data(step_id) do
    case Invocation.get_step_with_dataclips(step_id) do
      nil ->
        {nil, nil}

      step ->
        input =
          case step.input_dataclip do
            %{body: body} when not is_nil(body) -> Scrubber.scrub_values(body)
            _ -> nil
          end

        output =
          case step.output_dataclip do
            %{body: body} when not is_nil(body) -> Scrubber.scrub_values(body)
            _ -> nil
          end

        {input, output}
    end
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
        Logger.info(
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
            Logger.info(
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
