defmodule Lightning.AiAssistant do
  @moduledoc """
  The AI assistant module.
  """

  alias Lightning.Accounts.User
  alias Lightning.AiAssistant.ChatSession
  alias Lightning.ApolloClient
  alias Lightning.Repo
  alias Lightning.Workflows.Job

  @doc """
  Creates a new session with the given job.

  **Example**

      iex> AiAssistant.new_session(%Lightning.Workflows.Job{
      ...>   body: "fn()",
      ...>   adaptor: "@openfn/language-common@latest"
      ...> })
      %Lightning.AiAssistant.ChatSession{
        expression: "fn()",
        adaptor: "@openfn/language-common@1.6.2",
        messages: []
      }

  > ℹ️ The `adaptor` field is resolved to the latest version when `@latest`
  > is provided as Apollo expects a specific version.
  """

  @spec new_session(Job.t(), User.t()) :: ChatSession.t()
  def new_session(job, user) do
    %ChatSession{
      id: Ecto.UUID.generate(),
      job_id: job.id,
      user_id: user.id,
      messages: []
    }
    |> put_expression_and_adaptor(job.body, job.adaptor)
  end

  @spec put_expression_and_adaptor(ChatSession.t(), String.t(), String.t()) ::
          ChatSession.t()
  def put_expression_and_adaptor(session, expression, adaptor) do
    %{
      session
      | expression: expression,
        adaptor: Lightning.AdaptorRegistry.resolve_adaptor(adaptor)
    }
  end

  @spec save_message!(ChatSession.t(), %{String.t() => any()}) :: Session.t()
  def save_message!(session, message) do
    messages = Enum.map(session.messages, &Map.take(&1, [:id]))

    session
    |> ChatSession.changeset(%{messages: messages ++ [message]})
    |> Repo.insert_or_update!()
  end

  @doc """
  Queries the AI assistant with the given content.

  Returns `{:ok, session}` if the query was successful, otherwise `:error`.

  **Example**

      iex> AiAssistant.query(session, "fn()")
      {:ok, session}
  """
  @spec query(ChatSession.t(), String.t()) :: {:ok, ChatSession.t()} | :error
  def query(session, content) do
    ApolloClient.query(
      content,
      %{expression: session.expression, adaptor: session.adaptor},
      build_history(session)
    )
    |> case do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        assist_resp = body["history"] |> Enum.reverse() |> hd()
        message = Map.merge(assist_resp, %{"sender" => "assistant"})
        {:ok, save_message!(session, message)}

      _ ->
        :error
    end
  end

  defp build_history(session) do
    case Enum.reverse(session.messages) do
      [%{sender: :user} | other] ->
        other
        |> Enum.reverse()
        |> Enum.map(fn message ->
          %{role: message.sender, content: message.content}
        end)

      messages ->
        Enum.map(messages, fn message ->
          %{role: message.sender, content: message.content}
        end)
    end
  end

  @doc """
  Checks if the user is authorized to access the AI assistant.
  """
  @spec authorized?(User.t()) :: boolean()
  def authorized?(user) do
    user.role == :superuser
  end

  @doc """
  Checks if the Apollo endpoint is available.
  """
  @spec endpoint_available?() :: boolean()
  def endpoint_available? do
    ApolloClient.test() == :ok
  end
end
