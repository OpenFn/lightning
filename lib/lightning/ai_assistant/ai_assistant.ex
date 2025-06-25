defmodule Lightning.AiAssistant do
  @moduledoc """
  The AI assistant context module for Lightning workflows.

  This module provides a comprehensive interface for managing AI-powered chat sessions
  within the Lightning platform. It handles two main types of AI assistance:

  1. **Job-specific assistance** - Helps users with coding tasks, debugging, and
     adaptor-specific guidance for individual workflow jobs
  2. **Workflow template generation** - Assists in creating complete workflow
     templates from natural language descriptions
  """

  import Ecto.Query, warn: false

  alias Ecto.Changeset
  alias Ecto.Multi
  alias Lightning.Accounts
  alias Lightning.Accounts.User
  alias Lightning.AiAssistant.ChatMessage
  alias Lightning.AiAssistant.ChatSession
  alias Lightning.ApolloClient
  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias Lightning.Services.UsageLimiter
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Workflow
  alias LightningWeb.Live.AiAssistant.PaginationMeta

  require Logger

  @title_max_length 40

  @doc """
  Returns the maximum allowed length for chat session titles.

  ## Examples

      iex> Lightning.AiAssistant.title_max_length()
      40

  """
  @spec title_max_length() :: non_neg_integer()
  def title_max_length, do: @title_max_length

  @doc """
  Checks if the AI assistant feature is enabled via application configuration.

  Verifies that both the Apollo endpoint URL and API key are properly configured,
  which are required for AI functionality.

  ## Returns

  `true` if AI assistant is properly configured and enabled, `false` otherwise.

  ## Examples

      if AiAssistant.enabled?() do
        # Show AI assistant UI elements
      else
        # Hide AI features or show configuration message
      end

  """
  @spec enabled?() :: boolean()
  def enabled? do
    endpoint = Lightning.Config.apollo(:endpoint)
    api_key = Lightning.Config.apollo(:ai_assistant_api_key)
    is_binary(endpoint) && is_binary(api_key)
  end

  @doc """
  Checks if the Apollo AI service endpoint is reachable and responding.

  Performs a connectivity test to ensure the external AI service is available
  before attempting to make actual queries.

  ## Returns

  `true` if the Apollo endpoint responds successfully, `false` otherwise.

  ## Examples

      case AiAssistant.endpoint_available?() do
        true ->
          # Proceed with AI queries
        false ->
          # Show service unavailable message
      end

  """
  @spec endpoint_available?() :: boolean()
  def endpoint_available? do
    ApolloClient.test() == :ok
  end

  @doc """
  Checks if a user has acknowledged the AI assistant disclaimer recently.

  Verifies that the user has read and accepted the AI assistant terms and conditions
  within the last 24 hours. This ensures users are aware of AI limitations and usage terms.

  ## Parameters

  - `user` - The `%User{}` struct to check

  ## Returns

  `true` if disclaimer was read within 24 hours, `false` otherwise.

  ## Examples

      if AiAssistant.user_has_read_disclaimer?(current_user) do
        # User can access AI features
      else
        # Show disclaimer dialog
      end

  """
  @spec user_has_read_disclaimer?(User.t()) :: boolean()
  def user_has_read_disclaimer?(user) do
    read_at =
      user
      |> Accounts.get_preference("ai_assistant.disclaimer_read_at")
      |> case do
        timestamp when is_binary(timestamp) -> String.to_integer(timestamp)
        other -> other
      end

    case read_at && DateTime.from_unix(read_at) do
      {:ok, datetime} ->
        # Disclaimer is valid for 24 hours
        DateTime.diff(DateTime.utc_now(), datetime, :hour) < 24

      _error ->
        false
    end
  end

  @doc """
  Records that a user has read and accepted the AI assistant disclaimer.

  Updates the user's preferences with a timestamp indicating when they
  acknowledged the AI assistant terms and conditions.

  ## Parameters

  - `user` - The `%User{}` who read the disclaimer

  ## Returns

  `{:ok, user}` - Successfully recorded disclaimer acceptance.

  ## Examples

      {:ok, updated_user} = AiAssistant.mark_disclaimer_read(current_user)

  """
  @spec mark_disclaimer_read(User.t()) :: {:ok, User.t()}
  def mark_disclaimer_read(user) do
    timestamp = DateTime.utc_now() |> DateTime.to_unix()

    Accounts.update_user_preference(
      user,
      "ai_assistant.disclaimer_read_at",
      timestamp
    )
  end

  @doc """
  Creates a new chat session for job-specific AI assistance.

  Initializes a new session with:
  - Generated UUID
  - Association with the specified job and user
  - Auto-generated title from the initial message content
  - Job's expression and adaptor context
  - The initial user message

  ## Parameters

  - `job` - The `%Job{}` struct this session will assist with
  - `user` - The `%User{}` creating the session
  - `content` - Initial message content that will become the session title

  ## Returns

  - `{:ok, session}` - Successfully created session with initial message
  - `{:error, changeset}` - Validation errors during creation

  ## Examples

      case AiAssistant.create_session(job, current_user, "Help debug my HTTP request") do
        {:ok, session} ->
          # Session created successfully
        {:error, changeset} ->
          # Handle validation errors
      end

  """
  @spec create_session(Job.t(), User.t(), String.t()) ::
          {:ok, ChatSession.t()} | {:error, Ecto.Changeset.t()}
  def create_session(job, user, content) do
    %ChatSession{
      id: Ecto.UUID.generate(),
      job_id: job.id,
      user_id: user.id,
      title: create_title(content),
      messages: []
    }
    |> put_expression_and_adaptor(job.body, job.adaptor)
    |> save_message(%{role: :user, content: content, user: user})
  end

  @doc """
  Creates a new chat session for workflow template generation.

  Initializes a session specifically for creating workflow templates:
  - Associates with a project rather than a specific job
  - Sets session type to "workflow_template"
  - Includes the initial user message describing the desired workflow

  ## Parameters

  - `project` - The `%Project{}` struct where the workflow will be created
  - `user` - The `%User{}` requesting the workflow template
  - `content` - Description of the desired workflow functionality

  ## Returns

  - `{:ok, session}` - Successfully created workflow session
  - `{:error, changeset}` - Validation errors during creation

  ## Examples

      case AiAssistant.create_workflow_session(project, user, "Create a daily data sync from Salesforce to PostgreSQL") do
        {:ok, session} ->
          # Ready to generate workflow template
        {:error, changeset} ->
          # Handle errors
      end

  """
  @spec create_workflow_session(Project.t(), User.t(), String.t()) ::
          {:ok, ChatSession.t()} | {:error, Ecto.Changeset.t()}
  def create_workflow_session(project, user, content) do
    %ChatSession{
      id: Ecto.UUID.generate(),
      project_id: project.id,
      session_type: "workflow_template",
      user_id: user.id,
      title: create_title(content),
      meta: %{},
      messages: []
    }
    |> save_message(%{role: :user, content: content, user: user})
  end

  @doc """
  Retrieves a chat session by ID with all related data preloaded.

  Fetches a complete chat session including:
  - All non-cancelled messages ordered by creation time
  - User information for each message
  - Session metadata
  - Project information (for workflow template sessions)

  ## Parameters

  - `id` - UUID string of the session to retrieve

  ## Returns

  A `ChatSession` struct with preloaded `:messages` and nested `:user` data.
  For workflow template sessions, the `:project` association is also preloaded.

  ## Raises

  `Ecto.NoResultsError` if no session exists with the given ID.

  ## Examples

      # Job session
      session = AiAssistant.get_session!("123e4567-e89b-12d3-a456-426614174000")
      IO.puts("Session has # {length(session.messages)} messages")

      # Workflow template session (includes project)
      session = AiAssistant.get_session!("workflow-session-id")
      IO.puts("Workflow for project: # {session.project.name}")

  """
  def get_session!(id) do
    session =
      ChatSession
      |> Repo.get!(id)
      |> Repo.preload(messages: {session_messages_query(), :user})

    if session.session_type == "workflow_template" do
      Repo.preload(session, :project)
    else
      session
    end
  end

  defp session_messages_query do
    from(m in ChatMessage,
      where: m.status != :cancelled,
      order_by: [asc: :inserted_at]
    )
  end

  @doc """
  Returns paginated chat sessions with metadata for improved user experience.

  Retrieves chat sessions associated with either a Project (workflow template sessions)
  or a Job (job-specific sessions). Results are paginated and include total counts
  and navigation metadata.

  ## Parameters

  - `resource` - A `%Project{}`, `%Job{}`, or `%Snapshot.Job{}` struct to filter sessions by
  - `sort_direction` - Sort order, either `:asc` or `:desc` (default: `:desc`)
  - `opts` - Keyword list of options:
    - `:offset` - Number of records to skip (default: 0)
    - `:limit` - Maximum number of records to return (default: 20)

  ## Returns

  A map containing:
  - `:sessions` - List of `ChatSession` structs with preloaded data
  - `:pagination` - `PaginationMeta` struct with navigation information

  ## Examples

      # Get recent sessions for a project
      %{sessions: sessions, pagination: meta} =
        AiAssistant.list_sessions(project, :desc, offset: 0, limit: 10)

      # Get older sessions for a job
      %{sessions: sessions, pagination: meta} =
        AiAssistant.list_sessions(job, :asc, offset: 10, limit: 5)

  """
  @spec list_sessions(Project.t() | Job.t(), :asc | :desc, keyword()) :: %{
          sessions: [ChatSession.t()],
          pagination: PaginationMeta.t()
        }
  def list_sessions(resource, sort_direction \\ :desc, opts \\ []) do
    offset = Keyword.get(opts, :offset, 0)
    limit = Keyword.get(opts, :limit, 20)

    {sessions, total_count} =
      case resource do
        %{__struct__: Lightning.Projects.Project} = project ->
          get_workflow_sessions_with_count(
            project,
            sort_direction,
            offset,
            limit
          )

        %{__struct__: struct_type} = job
        when struct_type in [
               Lightning.Workflows.Job,
               Lightning.Workflows.Snapshot.Job
             ] ->
          get_job_sessions_with_count(job, sort_direction, offset, limit)
      end

    pagination =
      PaginationMeta.new(offset + length(sessions), limit, total_count)

    %{sessions: sessions, pagination: pagination}
  end

  @doc """
  Checks if additional sessions are available beyond the current count.

  This is a convenience function to determine if there are more sessions
  to load without fetching the actual data. Useful for "Load More" UI patterns.

  ## Parameters

  - `resource` - A `%Project{}` or `%Job{}` struct
  - `current_count` - Number of sessions already loaded

  ## Returns

  `true` if more sessions exist, `false` otherwise.

  ## Examples

      if AiAssistant.has_more_sessions?(project, 20) do
        # Show "Load More" button
      end

  """
  @spec has_more_sessions?(Project.t() | Job.t(), integer()) :: boolean()
  def has_more_sessions?(resource, current_count) do
    %{pagination: pagination} =
      list_sessions(resource, :desc, offset: current_count, limit: 1)

    pagination.has_next_page
  end

  @doc """
  Adds job-specific context to a chat session for enhanced AI assistance.

  Enriches a session with the job's expression code and adaptor information,
  enabling the AI to provide more targeted and relevant assistance.

  ## Parameters

  - `session` - The `%ChatSession{}` to enhance
  - `expression` - The job's expression code as a string
  - `adaptor` - The adaptor name/identifier for the job

  ## Returns

  An updated `ChatSession` struct with `:expression` and `:adaptor` fields populated.
  The adaptor is resolved through `Lightning.AdaptorRegistry`.

  ## Examples

      enhanced_session = AiAssistant.put_expression_and_adaptor(
        session,
        "fn(state) => { return {...state, processed: true}; }",
        "@openfn/language-http"
      )

  """
  @spec put_expression_and_adaptor(ChatSession.t(), String.t(), String.t()) ::
          ChatSession.t()
  def put_expression_and_adaptor(session, expression, adaptor) do
    %{
      session
      | expression: expression,
        adaptor: Lightning.AdaptorRegistry.resolve_adaptor(adaptor)
    }
  end

  @doc """
  Associates a workflow with a chat session.

  Links a generated workflow to the session that created it, enabling tracking
  and future modifications through the same conversation context.

  ## Parameters

  - `session` - The `%ChatSession{}` that generated the workflow
  - `workflow` - The `%Workflow{}` struct to associate

  ## Returns

  - `{:ok, session}` - Successfully linked workflow to session
  - `{:error, changeset}` - Association failed with validation errors

  ## Examples

      {:ok, updated_session} = AiAssistant.associate_workflow(session, new_workflow)

  """
  @spec associate_workflow(ChatSession.t(), Workflow.t()) ::
          {:ok, ChatSession.t()} | {:error, Ecto.Changeset.t()}
  def associate_workflow(session, workflow) do
    session
    |> ChatSession.changeset(%{workflow_id: workflow.id})
    |> Repo.update()
  end

  @doc """
  Saves a message to an existing chat session.

  Adds a new message to the session's message history and updates the session.
  For assistant messages, this also triggers AI usage tracking and limit enforcement.

  ## Parameters

  - `session` - The target `%ChatSession{}`
  - `message` - Map containing message data with keys like `:role`, `:content`, `:user`
  - `usage` - Map containing AI usage metrics (default: `%{}`)
  - `meta` - Optional metadata to update on the session (default: `nil`)

  ## Returns

  - `{:ok, session}` - Successfully saved message and updated session
  - `{:error, changeset}` - Validation or database errors

  ## Examples

      # Save user message
      {:ok, updated_session} = AiAssistant.save_message(session, %{
        role: :user,
        content: "How do I handle errors?",
        user: current_user
      })

      # Save assistant response with usage tracking
      {:ok, updated_session} = AiAssistant.save_message(session, %{
        role: :assistant,
        content: "Here's how to handle errors..."
      }, %{tokens_used: 150, cost: 0.003})

  """
  @spec save_message(ChatSession.t(), map(), map(), map() | nil) ::
          {:ok, ChatSession.t()} | {:error, Ecto.Changeset.t()}
  def save_message(session, message, usage \\ %{}, meta \\ nil) do
    messages = Enum.map(session.messages, &Map.take(&1, [:id]))

    Multi.new()
    |> Multi.put(:usage, usage)
    |> Multi.put(:message, message)
    |> Multi.insert_or_update(
      :upsert,
      ChatSession.changeset(session, %{
        messages: messages ++ [message],
        meta: meta || session.meta
      })
    )
    |> Multi.merge(&maybe_increment_ai_usage/1)
    |> Repo.transaction()
    |> case do
      {:ok, %{upsert: session}} -> {:ok, session}
      {:error, _operation, changeset, _changes} -> {:error, changeset}
    end
  end

  @doc """
  Updates the status of a specific message within a chat session.

  Changes the status of an individual message (e.g., from `:pending` to `:success` or `:error`)
  and returns the refreshed session with updated data.

  ## Parameters

  - `session` - The `%ChatSession{}` containing the message
  - `message` - The specific `%ChatMessage{}` to update
  - `status` - New status atom (e.g., `:pending`, `:success`, `:error`, `:cancelled`)

  ## Returns

  - `{:ok, session}` - Successfully updated message, returns refreshed session
  - `{:error, changeset}` - Update failed with validation errors

  ## Examples

      # Mark a pending message as successful
      {:ok, updated_session} = AiAssistant.update_message_status(
        session,
        pending_message,
        :success
      )

      # Mark a message as cancelled
      {:ok, updated_session} = AiAssistant.update_message_status(
        session,
        message,
        :cancelled
      )

  """
  @spec update_message_status(ChatSession.t(), ChatMessage.t(), atom()) ::
          {:ok, ChatSession.t()} | {:error, Changeset.t()}
  def update_message_status(session, message, status) do
    case Repo.update(ChatMessage.changeset(message, %{status: status})) do
      {:ok, _updated_message} ->
        {:ok,
         session
         |> Repo.preload([messages: {session_messages_query(), :user}],
           force: true
         )}

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  @doc """
  Finds all pending user messages in a chat session.

  Retrieves messages that have been sent by users but are still waiting
  for processing or AI responses. Useful for identifying stuck or failed requests.

  ## Parameters

  - `session` - The `%ChatSession{}` to search

  ## Returns

  List of `%ChatMessage{}` structs with `:role` of `:user` and `:status` of `:pending`.

  ## Examples

      pending_messages = AiAssistant.find_pending_user_messages(session)

      if length(pending_messages) > 0 do
        # Handle stuck messages
      end

  """
  @spec find_pending_user_messages(ChatSession.t()) :: [ChatMessage.t()]
  def find_pending_user_messages(session) do
    session.messages
    |> Enum.filter(&(&1.role == :user && &1.status == :pending))
  end

  @doc """
  Queries the AI assistant for job-specific code assistance.

  Sends a user query to the Apollo AI service along with job context (expression and adaptor)
  and conversation history. The AI provides targeted assistance for coding tasks, debugging,
  and adaptor-specific guidance.

  ## Parameters

  - `session` - The job-specific `%ChatSession{}` with expression and adaptor context
  - `content` - User's question or request for assistance

  ## Returns

  - `{:ok, session}` - AI responded successfully, session updated with response
  - `{:error, reason}` - Query failed, reason is either a string error message or changeset

  ## Examples

      case AiAssistant.query(session, "Why is my HTTP request failing?") do
        {:ok, updated_session} ->
          # AI provided assistance, check session.messages for response
        {:error, "Request timed out. Please try again."} ->
          # Handle timeout
        {:error, changeset} ->
          # Handle validation errors
      end

  """
  @spec query(ChatSession.t(), String.t(), map()) ::
          {:ok, ChatSession.t()} | {:error, String.t() | Ecto.Changeset.t()}
  def query(session, content, opts \\ %{}) do
    Logger.metadata(prompt_size: byte_size(content), session_id: session.id)
    pending_user_message = find_pending_user_message(session, content)

    context =
      build_context(
        %{
          expression: session.expression,
          adaptor: session.adaptor,
          log: session.logs
        },
        opts
      )

    ApolloClient.query(
      content,
      context,
      build_history(session),
      session.meta || %{}
    )
    |> handle_apollo_resp(session, pending_user_message)
  end

  defp build_context(context, opts) do
    Enum.reduce(opts, context, fn
      {:code, false}, acc ->
        Map.drop(acc, [:expression])

      {:logs, false}, acc ->
        Map.drop(acc, [:log])

      _opt, acc ->
        acc
    end)
  end

  @doc """
  Queries the AI service for workflow template generation.

  Sends a request to generate or modify workflow templates based on user requirements.
  Can include validation errors from previous attempts to help the AI provide corrections.

  ## Parameters

  - `session` - The workflow template `%ChatSession{}`
  - `content` - User's description of desired workflow functionality or modifications
  - `errors` - Optional string containing validation errors from previous workflow attempts

  ## Returns

  - `{:ok, session}` - Workflow template generated successfully
  - `{:error, reason}` - Generation failed, reason is either a string error message or changeset

  ## Examples

      # Initial workflow request
      {:ok, session} = AiAssistant.query_workflow(
        session,
        "Create a workflow that syncs Salesforce contacts to a Google Sheet daily"
      )

      # Request with error corrections
      {:ok, session} = AiAssistant.query_workflow(
        session,
        "Fix the validation errors",
        "Invalid cron expression: '0 0 * * 8'"
      )

  """
  @spec query_workflow(ChatSession.t(), String.t(), String.t() | nil) ::
          {:ok, ChatSession.t()} | {:error, String.t() | Ecto.Changeset.t()}
  def query_workflow(session, content, errors \\ nil) do
    pending_user_message = find_pending_user_message(session, content)

    latest_yaml = get_latest_workflow_yaml(session)

    ApolloClient.workflow_chat(
      content,
      latest_yaml,
      errors,
      build_history(session),
      session.meta || %{}
    )
    |> handle_workflow_response(session, pending_user_message)
  end

  defp get_workflow_sessions_with_count(project, sort_direction, offset, limit) do
    total_count =
      from(s in ChatSession,
        where:
          s.project_id == ^project.id and s.session_type == "workflow_template",
        select: count(s.id)
      )
      |> Repo.one()

    sessions =
      from(s in ChatSession,
        where:
          s.project_id == ^project.id and s.session_type == "workflow_template",
        left_join: m in assoc(s, :messages),
        group_by: [s.id, s.title, s.updated_at, s.inserted_at],
        select: %{s | message_count: count(m.id)},
        order_by: [{^sort_direction, s.updated_at}],
        preload: [:user],
        limit: ^limit,
        offset: ^offset
      )
      |> Repo.all()

    {sessions, total_count}
  end

  defp get_job_sessions_with_count(job, sort_direction, offset, limit) do
    total_count =
      from(s in ChatSession,
        where: s.job_id == ^job.id,
        select: count(s.id)
      )
      |> Repo.one()

    sessions =
      from(s in ChatSession,
        where: s.job_id == ^job.id,
        left_join: m in assoc(s, :messages),
        group_by: [s.id, s.title, s.updated_at, s.inserted_at],
        select: %{s | message_count: count(m.id)},
        order_by: [{^sort_direction, s.updated_at}],
        preload: [:user],
        limit: ^limit,
        offset: ^offset
      )
      |> Repo.all()

    {sessions, total_count}
  end

  defp create_title(content) do
    case String.contains?(content, " ") do
      true ->
        content
        |> String.split(" ")
        |> Enum.reduce_while("", fn word, acc ->
          new_acc = if acc == "", do: word, else: acc <> " " <> word

          if String.length(new_acc) > @title_max_length do
            {:halt, acc}
          else
            {:cont, new_acc}
          end
        end)
        |> String.replace(~r/[.!?,;:]$/, "")

      false ->
        content
        |> String.slice(0, @title_max_length)
        |> String.replace(~r/[.!?,;:]$/, "")
    end
  end

  defp handle_apollo_resp(
         {:ok, %Tesla.Env{status: status, body: body}},
         session,
         pending_user_message
       )
       when status in 200..299 do
    message = body["history"] |> Enum.reverse() |> hd()

    case save_message(session, message, body["usage"], body["meta"]) do
      {:ok, updated_session} ->
        if pending_user_message do
          update_message_status(updated_session, pending_user_message, :success)
        else
          {:ok, updated_session}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp handle_apollo_resp(error_response, session, pending_user_message) do
    if pending_user_message do
      update_message_status(session, pending_user_message, :error)
    end

    case error_response do
      {:ok, %Tesla.Env{status: status, body: body}}
      when status not in 200..299 ->
        error_message = body["message"]

        Logger.error("AI query failed for session: #{error_message}")

        {:error, error_message}

      {:error, :timeout} ->
        Logger.error("AI query timed out")
        {:error, "Request timed out. Please try again."}

      {:error, :econnrefused} ->
        Logger.error("Connection refused to AI server")
        {:error, "Unable to reach the AI server. Please try again later."}

      unexpected_error ->
        Logger.error("Unexpected error: #{inspect(unexpected_error)}")

        {:error, "Oops! Something went wrong. Please try again."}
    end
  end

  defp handle_workflow_response(
         {:ok, %Tesla.Env{status: status, body: body}},
         session,
         pending_user_message
       )
       when status in 200..299 do
    case save_message(
           session,
           %{
             role: :assistant,
             content: body["response"],
             workflow_code: body["response_yaml"]
           },
           body["usage"] || %{}
         ) do
      {:ok, updated_session} ->
        if pending_user_message do
          update_message_status(updated_session, pending_user_message, :success)
        else
          {:ok, updated_session}
        end

      {:error, changeset} ->
        {:error, changeset}
    end
  end

  defp handle_workflow_response(error_response, session, pending_user_message) do
    if pending_user_message do
      update_message_status(session, pending_user_message, :error)
    end

    case error_response do
      {:ok, %Tesla.Env{status: status, body: body}}
      when status not in 200..299 ->
        error_message = body["message"]

        Logger.error(
          "Workflow AI query failed for session #{session.id}: #{error_message}"
        )

        {:error, error_message}

      {:error, reason} ->
        Logger.error(
          "Workflow AI query failed for session #{session.id}: #{inspect(reason)}"
        )

        error_message =
          case reason do
            :timeout ->
              "Request timed out. Please try again."

            :econnrefused ->
              "Unable to reach the AI server. Please try again later."

            _ ->
              "Oops! Something went wrong. Please try again."
          end

        {:error, error_message}
    end
  end

  defp get_latest_workflow_yaml(session) do
    session.messages
    |> Enum.reverse()
    |> Enum.find_value(nil, fn
      %{role: :assistant, workflow_code: yaml} when not is_nil(yaml) -> yaml
      _ -> nil
    end)
  end

  defp build_history(session) do
    case Enum.reverse(session.messages) do
      [%{role: :user} | other] ->
        other
        |> Enum.reverse()
        |> Enum.map(&Map.take(&1, [:role, :content]))

      messages ->
        Enum.map(messages, &Map.take(&1, [:role, :content]))
    end
  end

  defp find_pending_user_message(session, content) do
    session.messages
    |> Enum.find(fn message ->
      message.role == :user &&
        message.status == :pending &&
        message.content == content
    end)
  end

  defp maybe_increment_ai_usage(%{
         upsert: session,
         message: %{"role" => "assistant"},
         usage: usage
       }) do
    maybe_increment_ai_usage(%{
      upsert: session,
      message: %{role: :assistant},
      usage: usage
    })
  end

  defp maybe_increment_ai_usage(%{
         upsert: session,
         message: %{role: :assistant},
         usage: usage
       }) do
    UsageLimiter.increment_ai_usage(session, usage)
  end

  defp maybe_increment_ai_usage(_user_role) do
    Multi.new()
  end
end
