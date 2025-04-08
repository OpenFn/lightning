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
  alias Lightning.Repo
  alias Lightning.Services.UsageLimiter
  alias Lightning.Workflows.Job

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
  def save_message(session, message, usage \\ %{}) do
    messages = Enum.map(session.messages, &Map.take(&1, [:id]))

    Multi.new()
    |> Multi.put(:usage, usage)
    |> Multi.put(:message, message)
    |> Multi.insert_or_update(
      :upsert,
      session
      |> ChatSession.changeset(%{messages: messages ++ [message]})
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
      build_history(session)
    )
    |> handle_apollo_resp(session)
  end

  defp handle_apollo_resp(
         {:ok, %Tesla.Env{status: status, body: body}},
         session
       )
       when status in 200..299 do
    message =
      body["history"]
      |> Enum.reverse()
      |> hd()
      |> Map.merge(%{
        "rag_results" => body["rag"],
        "prompt" => body["system_message"]
      })

    save_message(session, message, body["usage"])
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
end
