defmodule Lightning.AiAssistant do
  @moduledoc """
  The AI assistant context module.

  Provides functions for managing AI assistant chat sessions, messages,
  and interactions with the Apollo AI service.
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

  def title_max_length, do: @title_max_length

  @doc """
  Returns paginated sessions with metadata for better UX.

  ## Parameters
    * resource - A Project or Job struct
    * sort_direction - :asc or :desc (default: :desc)
    * opts - Keyword list with :offset and :limit

  ## Returns
    * %{sessions: [ChatSession.t()], pagination: PaginationMeta.t()}
  """
  @spec list_sessions(
          Project.t() | Job.t(),
          :asc | :desc,
          keyword()
        ) :: %{sessions: [ChatSession.t()], pagination: PaginationMeta.t()}
  def list_sessions(resource, sort_direction \\ :desc, opts \\ []) do
    offset = Keyword.get(opts, :offset, 0)
    limit = Keyword.get(opts, :limit, 20)

    {sessions, total_count} =
      case resource do
        %Project{} = project ->
          get_workflow_sessions_with_count(
            project,
            sort_direction,
            offset,
            limit
          )

        %Job{} = job ->
          get_job_sessions_with_count(job, sort_direction, offset, limit)
      end

    pagination =
      PaginationMeta.new(offset + length(sessions), limit, total_count)

    %{sessions: sessions, pagination: pagination}
  end

  @doc """
  Checks if more sessions are available beyond the current count.
  """
  @spec has_more_sessions?(Project.t() | Job.t(), integer()) :: boolean()
  def has_more_sessions?(resource, current_count) do
    %{pagination: pagination} =
      list_sessions(resource, :desc, offset: current_count, limit: 1)

    pagination.has_next_page
  end

  @doc """
  Gets a session by ID with preloaded messages and users.
  """
  @spec get_session!(Ecto.UUID.t()) :: ChatSession.t()
  def get_session!(id) do
    message_query =
      from(m in ChatMessage,
        where: m.status != :cancelled,
        order_by: [asc: :inserted_at]
      )

    ChatSession
    |> Repo.get!(id)
    |> Repo.preload(messages: {message_query, :user})
  end

  @doc """
  Adds expression and adaptor context to a session for job-specific assistance.
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
  Creates a new job-specific chat session.
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
  Creates a new workflow template session.
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
  Saves a message to a chat session.
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
  """
  @spec update_message_status(ChatSession.t(), ChatMessage.t(), atom()) ::
          {:ok, ChatSession.t()} | {:error, Changeset.t()}
  def update_message_status(session, message, status) do
    case Repo.update(ChatMessage.changeset(message, %{status: status})) do
      {:ok, _updated_message} -> {:ok, get_session!(session.id)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @doc """
  Queries the AI assistant for job code assistance.

  Returns `{:ok, session}` if the query was successful, otherwise `{:error, reason}`.
  """
  @spec query(ChatSession.t(), String.t()) ::
          {:ok, ChatSession.t()} | {:error, String.t() | Ecto.Changeset.t()}
  def query(session, content) do
    pending_user_message = find_pending_user_message(session, content)

    ApolloClient.query(
      content,
      %{expression: session.expression, adaptor: session.adaptor},
      build_history(session),
      session.meta || %{}
    )
    |> handle_apollo_resp(session, pending_user_message)
  end

  @doc """
  Queries the workflow_chat service for workflow template generation.

  Returns `{:ok, session}` if the query was successful, otherwise `{:error, reason}`.
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

  @doc """
  Associates a workflow with a chat session.
  """
  @spec associate_workflow(ChatSession.t(), Workflow.t()) ::
          {:ok, ChatSession.t()} | {:error, Ecto.Changeset.t()}
  def associate_workflow(session, workflow) do
    session
    |> ChatSession.changeset(%{workflow_id: workflow.id})
    |> Repo.update()
  end

  @doc """
  Checks if user has read the AI assistant disclaimer within 24 hours.
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
  Marks the disclaimer as read for the user.
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
  Checks if the AI assistant is enabled via configuration.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    endpoint = Lightning.Config.apollo(:endpoint)
    api_key = Lightning.Config.apollo(:ai_assistant_api_key)
    is_binary(endpoint) && is_binary(api_key)
  end

  @doc """
  Checks if the Apollo endpoint is available.
  """
  @spec endpoint_available?() :: boolean()
  def endpoint_available? do
    ApolloClient.test() == :ok
  end

  @doc """
  Finds all pending user messages in a session.
  """
  def find_pending_user_messages(session) do
    session.messages
    |> Enum.filter(&(&1.role == :user && &1.status == :pending))
  end

  defp get_workflow_sessions_with_count(project, sort_direction, offset, limit) do
    # Get total count
    total_count =
      from(s in ChatSession,
        where:
          s.project_id == ^project.id and s.session_type == "workflow_template",
        select: count(s.id)
      )
      |> Repo.one()

    # Get sessions with message count
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
    # Get total count
    total_count =
      from(s in ChatSession,
        where: s.job_id == ^job.id,
        select: count(s.id)
      )
      |> Repo.one()

    # Get sessions with message count
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

        Logger.error(
          "AI query failed for session #{session.id}: #{error_message}"
        )

        {:error, error_message}

      {:error, :timeout} ->
        Logger.error("AI query timed out for session #{session.id}")
        {:error, "Request timed out. Please try again."}

      {:error, :econnrefused} ->
        Logger.error("Connection to AI server refused for session #{session.id}")
        {:error, "Unable to reach the AI server. Please try again later."}

      unexpected_error ->
        Logger.error(
          "Unexpected error for session #{session.id}: #{inspect(unexpected_error)}"
        )

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
