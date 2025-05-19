defmodule Lightning.AiAssistant do
  @moduledoc """
  The AI assistant module.
  """

  import Ecto.Query

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

  require Logger

  @title_max_length 40

  def title_max_length, do: @title_max_length

  @spec put_expression_and_adaptor(ChatSession.t(), String.t(), String.t()) ::
          ChatSession.t()
  def put_expression_and_adaptor(session, expression, adaptor) do
    %{
      session
      | expression: expression,
        adaptor: Lightning.AdaptorRegistry.resolve_adaptor(adaptor)
    }
  end

  @spec list_sessions_for_job(Job.t(), :asc | :desc) ::
          [ChatSession.t(), ...] | []
  def list_sessions_for_job(job, sort_direction \\ :desc) do
    Repo.all(
      from s in ChatSession,
        where: s.job_id == ^job.id,
        order_by: [{^sort_direction, :updated_at}],
        preload: [:user]
    )
  end

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

  defp create_title(content) do
    case String.contains?(content, " ") do
      true ->
        content
        |> String.split(" ")
        |> Enum.reduce_while("", fn word, acc ->
          if String.length(acc <> " " <> word) > @title_max_length,
            do: {:halt, acc},
            else: {:cont, acc <> " " <> word}
        end)
        |> String.trim()
        |> String.replace(~r/[.!?,;:]$/, "")

      false ->
        content
        |> String.slice(0, @title_max_length)
        |> String.replace(~r/[.!?,;:]$/, "")
    end
  end

  @spec save_message(ChatSession.t(), %{any() => any()}) ::
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
      {:ok, %{upsert: session}} ->
        {:ok, session}

      {:error, _operation, changeset, _changes} ->
        {:error, changeset}
    end
  end

  @doc """
  Queries the AI assistant with the given content.

  Returns `{:ok, session}` if the query was successful, otherwise `{:error, reason}`.

  **Example**

      iex> AiAssistant.query(session, "fn()")
      {:ok, session}
  """
  @spec query(ChatSession.t(), String.t()) ::
          {:ok, ChatSession.t()}
          | {:error, String.t() | Ecto.Changeset.t()}
  def query(session, content) do
    ApolloClient.query(
      content,
      %{expression: session.expression, adaptor: session.adaptor},
      build_history(session),
      session.meta || %{}
    )
    |> handle_apollo_resp(session)
  end

  defp handle_apollo_resp(
         {:ok, %Tesla.Env{status: status, body: body}},
         session
       )
       when status in 200..299 do
    message = body["history"] |> Enum.reverse() |> hd()
    save_message(session, message, body["usage"], body["meta"])
  end

  defp handle_apollo_resp(
         {:ok, %Tesla.Env{status: status, body: body}},
         session
       )
       when status not in 200..299 do
    error_message = body["message"]
    Logger.error("AI query failed for session #{session.id}: #{error_message}")
    {:error, error_message}
  end

  defp handle_apollo_resp({:error, :timeout}, session) do
    Logger.error("AI query timed out for session #{session.id}")
    {:error, "Request timed out. Please try again."}
  end

  defp handle_apollo_resp({:error, :econnrefused}, session) do
    Logger.error("Connection to AI server refused for session #{session.id}")
    {:error, "Unable to reach the AI server. Please try again later."}
  end

  defp handle_apollo_resp(unexpected_error, session) do
    Logger.error(
      "Received an unexpected error for session #{session.id}: #{inspect(unexpected_error)}"
    )

    {:error, "Oops! Something went wrong. Please try again."}
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

  @doc """
  Checks if the AI assistant is enabled.
  """
  @spec enabled?() :: boolean()
  def enabled? do
    endpoint = Lightning.Config.apollo(:endpoint)
    api_key = Lightning.Config.apollo(:ai_assistant_api_key)

    is_binary(endpoint) && is_binary(api_key)
  end

  @spec user_has_read_disclaimer?(User.t()) :: boolean()
  def user_has_read_disclaimer?(user) do
    read_at =
      user
      |> Accounts.get_preference("ai_assistant.disclaimer_read_at")
      |> case do
        timestamp when is_binary(timestamp) ->
          String.to_integer(timestamp)

        other ->
          other
      end

    case read_at && DateTime.from_unix(read_at) do
      {:ok, datetime} ->
        # you've read disclaimer only if timestamp is less than 24 hours
        DateTime.diff(DateTime.utc_now(), datetime, :hour) < 24

      _error ->
        false
    end
  end

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
  Checks if the Apollo endpoint is available.
  """
  @spec endpoint_available?() :: boolean()
  def endpoint_available? do
    ApolloClient.test() == :ok
  end

  @doc """
  Updates the status of a specific message within a chat session.

  Returns `{:ok, session}` if the update is successful, otherwise `{:error, changeset}`.
  """
  @spec update_message_status(ChatSession.t(), ChatMessage.t(), atom()) ::
          {:ok, ChatSession.t()} | {:error, Changeset.t()}
  def update_message_status(session, message, status) do
    case Repo.update(ChatMessage.changeset(message, %{status: status})) do
      {:ok, _updated_message} -> {:ok, get_session!(session.id)}
      {:error, changeset} -> {:error, changeset}
    end
  end

  @spec maybe_increment_ai_usage(%{
          upsert: ChatSession.t(),
          message: map(),
          usage: map()
        }) :: Ecto.Multi.t()
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

  @doc """
  Lists all workflow template sessions for a project.
  """
  @spec list_workflow_sessions_for_project(
          Project.t() | Ecto.UUID.t(),
          :asc | :desc
        ) ::
          [ChatSession.t()] | []
  def list_workflow_sessions_for_project(project, sort_direction \\ :desc)

  def list_workflow_sessions_for_project(
        %Project{id: project_id},
        sort_direction
      ) do
    list_workflow_sessions_for_project(project_id, sort_direction)
  end

  def list_workflow_sessions_for_project(project_id, sort_direction)
      when is_binary(project_id) do
    Repo.all(
      from s in ChatSession,
        where:
          s.project_id == ^project_id and s.session_type == "workflow_template",
        order_by: [{^sort_direction, :updated_at}],
        preload: [:user]
    )
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
  Queries the workflow_chat service with the given content.

  Returns `{:ok, session}` if the query was successful, otherwise `{:error, reason}`.
  """
  @spec query_workflow(ChatSession.t(), String.t(), String.t() | nil) ::
          {:ok, ChatSession.t()}
          | {:error, String.t() | Ecto.Changeset.t()}
  def query_workflow(session, content, errors \\ nil) do
    # Find the latest YAML from previous messages
    latest_yaml =
      session.messages
      |> Enum.reverse()
      |> Enum.find_value(nil, fn
        %{role: :assistant, yaml: yaml} when not is_nil(yaml) -> yaml
        _ -> nil
      end)

    ApolloClient.workflow_chat(
      content,
      latest_yaml,
      errors,
      build_history(session),
      session.meta || %{}
    )
    |> handle_workflow_response(session)
  end

  defp handle_workflow_response(
         {:ok, %Tesla.Env{status: status, body: body}},
         session
       )
       when status in 200..299 do
    save_message(
      session,
      %{
        role: :assistant,
        content: body["response"],
        workflow_code: body["response_yaml"]
      },
      body["usage"] || %{}
    )
  end

  defp handle_workflow_response(
         {:ok, %Tesla.Env{status: status, body: body}},
         session
       )
       when status not in 200..299 do
    error_message = body["message"]

    Logger.error(
      "Workflow AI query failed for session #{session.id}: #{error_message}"
    )

    {:error, error_message}
  end

  defp handle_workflow_response({:error, reason}, session) do
    Logger.error(
      "Workflow AI query failed for session #{session.id}: #{inspect(reason)}"
    )

    error_message =
      case reason do
        :timeout -> "Request timed out. Please try again."
        :econnrefused -> "Unable to reach the AI server. Please try again later."
        _ -> "Oops! Something went wrong. Please try again."
      end

    {:error, error_message}
  end
end
