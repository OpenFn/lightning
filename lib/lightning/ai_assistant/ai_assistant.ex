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
  alias Lightning.AiAssistant.MessageProcessor
  alias Lightning.ApolloClient
  alias Lightning.Projects.Project
  alias Lightning.Repo
  alias Lightning.Services.UsageLimiter
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Workflow
  alias LightningWeb.Live.AiAssistant.PaginationMeta

  require Logger

  @title_max_length 40
  @success_status_range 200..299

  @type opts :: keyword()

  @doc """
  Returns the maximum allowed length for chat session titles.
  """
  @spec title_max_length() :: non_neg_integer()
  def title_max_length, do: @title_max_length

  @doc """
  Checks if the AI assistant feature is enabled via application configuration.

  Verifies that both the Apollo endpoint URL and API key are properly configured,
  which are required for AI functionality.

  ## Returns

  `true` if AI assistant is properly configured and enabled, `false` otherwise.
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
  - Association with the specified job and user
  - Auto-generated title from the initial message content
  - Job's expression and adaptor context (virtual fields)
  - The initial user message

  ## Parameters

  - `job` - The `%Job{}` struct this session will assist with
  - `user` - The `%User{}` creating the session
  - `content` - Initial message content that will become the session title
  - `opts` - Keyword list of options:
    - `:meta` - Optional metadata for the session
    - `:code` - Optional workflow code for the initial message

  ## Returns

  - `{:ok, session}` - Successfully created session with initial message
  - `{:error, changeset}` - Validation errors during creation
  """
  @spec create_session(Job.t(), User.t(), String.t(), opts()) ::
          {:ok, ChatSession.t()} | {:error, Ecto.Changeset.t()}
  def create_session(job, user, content, opts \\ []) do
    meta = Keyword.get(opts, :meta, %{})

    session_attrs = %{
      job_id: job.id,
      user_id: user.id,
      title: create_title(content),
      session_type: "job_code",
      meta: meta
    }

    Multi.new()
    |> Multi.insert(
      :session,
      ChatSession.changeset(%ChatSession{}, session_attrs)
    )
    |> Multi.run(:session_with_message, fn repo, %{session: session} ->
      session
      |> repo.preload(:messages)
      |> put_expression_and_adaptor(job.body, job.adaptor)
      |> save_message(%{role: :user, content: content, user: user}, opts)
    end)
    |> Repo.transaction()
    |> handle_transaction_result()
  end

  @doc """
  Creates a new chat session for workflow template generation.

  Initializes a session specifically for creating workflow templates:
  - Associates with a project and optionally an existing workflow
  - Sets session type to "workflow_template"
  - Includes the initial user message describing the desired workflow

  ## Parameters

  - `project` - The `%Project{}` struct where the workflow will be created
  - `workflow` - The `%Workflow{}` struct to associate with the session, or `nil` for new workflows
  - `user` - The `%User{}` requesting the workflow template
  - `content` - Description of the desired workflow functionality
  - `opts` - Keyword list of options:
    - `:meta` - Optional metadata for the session
    - `:code` - Optional workflow code for the initial message

  ## Returns

  - `{:ok, session}` - Successfully created workflow session with initial message
  - `{:error, changeset}` - Validation errors during creation
  """
  @spec create_workflow_session(
          Project.t(),
          Workflow.t() | nil,
          User.t(),
          String.t(),
          opts()
        ) ::
          {:ok, ChatSession.t()} | {:error, Ecto.Changeset.t()}
  def create_workflow_session(project, workflow, user, content, opts \\ []) do
    meta = Keyword.get(opts, :meta, %{})

    session_attrs = %{
      project_id: project.id,
      workflow_id: workflow && workflow.id,
      session_type: "workflow_template",
      user_id: user.id,
      title: create_title(content),
      meta: meta
    }

    Multi.new()
    |> Multi.insert(
      :session,
      ChatSession.changeset(%ChatSession{}, session_attrs)
    )
    |> Multi.run(:session_with_message, fn repo, %{session: session} ->
      session
      |> repo.preload(:messages)
      |> save_message(%{role: :user, content: content, user: user}, opts)
    end)
    |> Repo.transaction()
    |> handle_transaction_result()
  end

  defp session_query(session_id, opts \\ []) do
    job_id = Keyword.get(opts, :job_id)

    query = from(s in ChatSession, where: s.id == ^session_id)

    if job_id do
      where(query, [s], s.job_id == ^job_id)
    else
      query
    end
  end

  defp preload_session(session) do
    session =
      Repo.preload(session, [:user, messages: {session_messages_query(), :user}])

    if session.session_type == "workflow_template" do
      Repo.preload(session, :project)
    else
      session
    end
  end

  @doc """
  Gets a session by ID.

  Returns the session or `nil` if not found.

  ## Examples

      iex> get_session(session_id)
      %ChatSession{}

      iex> get_session("nonexistent")
      nil
  """
  def get_session(session_id) when is_binary(session_id) do
    case session_query(session_id) |> Repo.one() do
      nil -> nil
      session -> preload_session(session)
    end
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
  """
  def get_session!(session_id) when is_binary(session_id) do
    session_query(session_id)
    |> Repo.one!()
    |> preload_session()
  end

  @doc """
  Gets a session scoped to a specific job.

  Returns the session or `nil` if not found or doesn't belong to the job.

  ## Examples

      iex> get_session(session_id, job)
      %ChatSession{}

      iex> get_session(session_id, different_job)
      nil
  """
  def get_session(session_id, %Job{id: job_id}) do
    case session_query(session_id, job_id: job_id) |> Repo.one() do
      nil -> nil
      session -> preload_session(session)
    end
  end

  @doc """
  Gets a session scoped to a specific job, raising if not found.

  ## Examples

      iex> get_session!(session_id, job)
      %ChatSession{}

      iex> get_session!(session_id, different_job)
      ** (Ecto.NoResultsError)
  """
  def get_session!(session_id, %Job{id: job_id}) do
    session_query(session_id, job_id: job_id)
    |> Repo.one!()
    |> preload_session()
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
  """
  @spec list_sessions(Project.t() | Job.t(), :asc | :desc, opts()) :: %{
          sessions: [ChatSession.t()],
          pagination: PaginationMeta.t()
        }
  def list_sessions(resource, sort_direction \\ :desc, opts \\ []) do
    offset = Keyword.get(opts, :offset, 0)
    limit = Keyword.get(opts, :limit, 20)

    {sessions, total_count} =
      case resource do
        %{__struct__: Lightning.Projects.Project} = project ->
          workflow = Keyword.get(opts, :workflow)

          get_workflow_sessions_with_count(
            project,
            workflow,
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
  Enriches a chat session with job-specific context.

  Loads the associated job and enriches the session with:
  - Job expression code and adaptor information
  - Run logs if following a specific run (via session.meta["follow_run_id"])

  ## Parameters
  - `session` - The chat session to enrich

  ## Returns
  The enriched session with job context loaded
  """
  @spec enrich_session_with_job_context(ChatSession.t()) :: ChatSession.t()
  def enrich_session_with_job_context(%{job_id: nil} = session), do: session

  def enrich_session_with_job_context(session) do
    job = Repo.get!(Lightning.Workflows.Job, session.job_id)

    session
    |> put_expression_and_adaptor(job.body, job.adaptor)
    |> maybe_add_run_logs()
  end

  @doc false
  defp maybe_add_run_logs(%{meta: %{"follow_run_id" => run_id}} = session)
       when not is_nil(run_id) do
    logs =
      Lightning.Invocation.assemble_logs_for_job_and_run(session.job_id, run_id)

    %{session | logs: logs}
  end

  defp maybe_add_run_logs(session), do: session

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
  - `message_attrs` - Map containing message data with keys like `:role`, `:content`, `:user`
  - `opts` - Keyword list of options:
    - `:usage` - Map containing AI usage metrics (default: `%{}`)
    - `:meta` - Session metadata to update (default: keeps existing)
    - `:code` - Optional workflow code to attach to the message

  ## Returns

  - `{:ok, session}` - Successfully saved message and updated session
  - `{:error, changeset}` - Validation or database errors
  """
  @spec save_message(ChatSession.t(), map(), opts()) ::
          {:ok, ChatSession.t()} | {:error, Ecto.Changeset.t()}
  def save_message(session, message_attrs, opts \\ []) do
    usage = Keyword.get(opts, :usage, %{})
    meta = Keyword.get(opts, :meta)
    code = Keyword.get(opts, :code)

    message_attrs =
      message_attrs
      |> Enum.into(%{}, fn {k, v} -> {to_string(k), v} end)
      |> Map.put("chat_session_id", session.id)
      |> Map.put("code", code)

    Multi.new()
    |> Multi.put(:usage, usage)
    |> Multi.insert(
      :message,
      ChatMessage.changeset(%ChatMessage{}, message_attrs)
    )
    |> Multi.update(:session, fn %{message: _message} ->
      ChatSession.changeset(session, %{meta: meta || session.meta})
    end)
    |> Multi.merge(&maybe_increment_ai_usage/1)
    |> Multi.run(:enqueue_if_user_message, fn _repo, %{message: message} ->
      if message.role == :user && message.status == :pending do
        Oban.insert(
          Lightning.Oban,
          MessageProcessor.new(%{message_id: message.id})
        )
      else
        {:ok, nil}
      end
    end)
    |> Repo.transaction()
    |> case do
      {:ok, %{session: session}} ->
        {:ok, Repo.preload(session, [messages: :user], force: true)}

      {:error, :message, changeset, _changes} ->
        {:error, changeset}

      {:error, :session, changeset, _changes} ->
        {:error, changeset}
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
  """
  @spec update_message_status(ChatSession.t(), ChatMessage.t(), atom()) ::
          {:ok, ChatSession.t()} | {:error, Changeset.t()}
  def update_message_status(session, message, status) do
    case Repo.update(ChatMessage.status_changeset(message, status)) do
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
  """
  @spec find_pending_user_messages(ChatSession.t()) :: [ChatMessage.t()]
  def find_pending_user_messages(session) do
    messages = session.messages || []
    Enum.filter(messages, &(&1.role == :user && &1.status == :pending))
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
  """
  @spec query(ChatSession.t(), String.t(), opts()) ::
          {:ok, ChatSession.t()} | {:error, String.t() | Ecto.Changeset.t()}
  def query(session, content, opts \\ []) do
    Logger.metadata(prompt_size: byte_size(content), session_id: session.id)

    context =
      build_context(
        %{
          expression: session.expression,
          adaptor: session.adaptor,
          log: session.logs
        },
        opts
      )

    history = build_history(session)
    meta = session.meta || %{}

    ApolloClient.job_chat(
      content,
      context: context,
      history: history,
      meta: meta
    )
    |> handle_ai_response(session, &build_job_message/1)
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
  - `opts` - Keyword list of options:
    - `:code` - Current YAML to modify (default: uses latest from session)
    - `:errors` - Validation errors from previous workflow attempts
    - `:meta` - Additional metadata to pass to the AI service (default: session.meta)

  ## Returns

  - `{:ok, session}` - Workflow template generated successfully
  - `{:error, reason}` - Generation failed, reason is either a string error message or changeset
  """
  @spec query_workflow(ChatSession.t(), String.t(), opts()) ::
          {:ok, ChatSession.t()} | {:error, String.t() | Ecto.Changeset.t()}
  def query_workflow(session, content, opts \\ []) do
    code = Keyword.get(opts, :code)
    errors = Keyword.get(opts, :errors)
    meta = Keyword.get(opts, :meta, session.meta || %{})

    Logger.metadata(prompt_size: byte_size(content), session_id: session.id)

    ApolloClient.workflow_chat(
      content,
      code: code,
      errors: errors,
      history: build_history(session),
      meta: meta
    )
    |> handle_ai_response(session, &build_workflow_message/1)
  end

  @doc """
  Resets a message status to pending and enqueues it for reprocessing.
  Handles both the database update and Oban job creation atomically.
  """
  def retry_message(message) do
    Multi.new()
    |> Multi.update(
      :message,
      Ecto.Changeset.change(message, %{status: :pending})
    )
    |> Multi.insert(
      :oban_job,
      MessageProcessor.new(%{message_id: message.id})
    )
    |> Repo.transaction()
    |> case do
      {:ok, %{message: message, oban_job: oban_job}} ->
        {:ok, {message, oban_job}}

      {:error, _op, changeset, _changes} ->
        {:error, changeset}
    end
  end

  defp get_workflow_sessions_with_count(
         project,
         workflow,
         sort_direction,
         offset,
         limit
       ) do
    base_query =
      from(s in ChatSession,
        where:
          s.project_id == ^project.id and s.session_type == "workflow_template"
      )

    query =
      if workflow do
        where(base_query, [s], s.workflow_id == ^workflow.id)
      else
        where(base_query, [s], is_nil(s.workflow_id))
      end

    total_count =
      query
      |> select([s], count(s.id))
      |> Repo.one()

    sessions =
      query
      |> join(:left, [s], m in assoc(s, :messages))
      |> group_by([s, m], [s.id, s.title, s.updated_at, s.inserted_at])
      |> select([s, m], %{s | message_count: count(m.id)})
      |> order_by([s, m], [{^sort_direction, s.updated_at}])
      |> preload([:user, :project])
      |> limit(^limit)
      |> offset(^offset)
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

  defp handle_ai_response(response, session, message_builder) do
    case response do
      {:ok, %Tesla.Env{status: status, body: body}}
      when status in @success_status_range ->
        {message_attrs, opts} = message_builder.(body)
        save_message(session, message_attrs, opts)

      error ->
        handle_error_response(error, session)
    end
  end

  defp handle_error_response(error_response, session) do
    case error_response do
      {:ok, %Tesla.Env{status: status, body: body}}
      when status not in @success_status_range ->
        error_message = body["message"]

        Logger.error(
          "AI query failed for session #{session.id}: #{error_message}"
        )

        {:error, error_message}

      {:error, :timeout} ->
        Logger.error("AI query timed out for session #{session.id}")
        {:error, "Request timed out. Please try again."}

      {:error, :econnrefused} ->
        Logger.error("Connection refused to AI server for session #{session.id}")
        {:error, "Unable to reach the AI server. Please try again later."}

      unexpected_error ->
        Logger.error(
          "Unexpected error for session #{session.id}: #{inspect(unexpected_error)}"
        )

        {:error, "Oops! Something went wrong. Please try again."}
    end
  end

  defp build_job_message(body) do
    message = body["history"] |> Enum.reverse() |> hd()
    message_attrs = Map.take(message, ["role", "content"])
    opts = [usage: body["usage"] || %{}, meta: body["meta"]]

    {message_attrs, opts}
  end

  defp build_workflow_message(body) do
    message_attrs = %{
      role: :assistant,
      content: body["response"]
    }

    opts = [
      usage: body["usage"] || %{},
      meta: body["meta"],
      code: body["response_yaml"]
    ]

    {message_attrs, opts}
  end

  defp build_history(session) do
    messages = session.messages || []

    case Enum.reverse(messages) do
      [%{role: :user} | other] ->
        other
        |> Enum.reverse()
        |> Enum.map(&Map.take(&1, [:role, :content]))

      messages ->
        Enum.map(messages, &Map.take(&1, [:role, :content]))
    end
  end

  defp maybe_increment_ai_usage(%{
         session: session,
         message: %{"role" => "assistant"},
         usage: usage
       }) do
    maybe_increment_ai_usage(%{
      session: session,
      message: %{role: :assistant},
      usage: usage
    })
  end

  defp maybe_increment_ai_usage(%{
         session: session,
         message: %{role: :assistant},
         usage: usage
       }) do
    UsageLimiter.increment_ai_usage(session, usage)
  end

  defp maybe_increment_ai_usage(_user_role) do
    Multi.new()
  end

  defp handle_transaction_result(result, success_key \\ :session_with_message) do
    case result do
      {:ok, %{^success_key => session}} -> {:ok, session}
      {:error, :session, changeset, _changes} -> {:error, changeset}
      {:error, ^success_key, changeset, _changes} -> {:error, changeset}
    end
  end
end
