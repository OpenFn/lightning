defmodule Lightning.AiAssistant do
  @moduledoc """
  The AI assistant module.
  """

  import Ecto.Query

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

  @spec list_sessions_for_job(Job.t()) :: [ChatSession.t(), ...] | []
  def list_sessions_for_job(job) do
    Repo.all(
      from s in ChatSession,
        where: s.job_id == ^job.id,
        order_by: [desc: :updated_at],
        preload: [:user]
    )
  end

  @spec get_session!(Ecto.UUID.t()) :: ChatSession.t()
  def get_session!(id) do
    ChatSession |> Repo.get!(id) |> Repo.preload(messages: :user)
  end

  @spec create_session!(Job.t(), User.t(), String.t()) :: ChatSession.t()
  def create_session!(job, user, content) do
    job
    |> new_session(user)
    |> struct(title: String.slice(content, 0, 20))
    |> save_message!(%{role: :user, content: content, user_id: user.id})
  end

  @spec save_message!(ChatSession.t(), %{any() => any()}) :: ChatSession.t()
  def save_message!(session, message) do
    messages = Enum.map(session.messages, &Map.take(&1, [:id]))

    session
    |> ChatSession.changeset(%{messages: messages ++ [message]})
    |> Repo.insert_or_update!()
  end

  @spec project_has_any_session?(Ecto.UUID.t()) :: boolean()
  def project_has_any_session?(project_id) do
    query =
      from s in ChatSession,
        join: j in assoc(s, :job),
        join: w in assoc(j, :workflow),
        where: w.project_id == ^project_id

    Repo.exists?(query)
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
        message = body["history"] |> Enum.reverse() |> hd()
        {:ok, save_message!(session, message)}

      _ ->
        :error
    end
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
    api_key = Lightning.Config.apollo(:openai_api_key)

    is_binary(endpoint) && is_binary(api_key)
  end

  @doc """
  Checks if the Apollo endpoint is available.
  """
  @spec endpoint_available?() :: boolean()
  def endpoint_available? do
    ApolloClient.test() == :ok
  end
end
