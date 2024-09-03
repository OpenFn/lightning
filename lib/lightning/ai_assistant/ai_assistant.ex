defmodule Lightning.AiAssistant do
  @moduledoc """
  The AI assistant module.
  """

  import Ecto.Query

  alias Ecto.Multi
  alias Lightning.Accounts.User
  alias Lightning.AiAssistant.ChatSession
  alias Lightning.ApolloClient
  alias Lightning.Repo
  alias Lightning.Workflows.Job
  alias Lightning.Workflows.Workflow

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

  @spec create_session(Job.t(), User.t(), String.t()) ::
          {:ok, ChatSession.t()} | {:error, Ecto.Changeset.t()}
  def create_session(job, user, content) do
    %{project_id: project_id} = Repo.get!(Workflow, job.workflow_id)

    %ChatSession{
      id: Ecto.UUID.generate(),
      job_id: job.id,
      project_id: project_id,
      user_id: user.id,
      title: String.slice(content, 0, 40),
      messages: []
    }
    |> put_expression_and_adaptor(job.body, job.adaptor)
    |> save_message(%{role: :user, content: content, user: user})
  end

  @spec save_message(ChatSession.t(), %{any() => any()}) ::
          {:ok, ChatSession.t()} | {:error, Ecto.Changeset.t()}
  def save_message(session, message) do
    # we can call the limiter at this point
    # note: we should only increment the counter when role is `:assistant`
    messages = Enum.map(session.messages, &Map.take(&1, [:id]))

    Multi.new()
    |> Multi.put(:message, message)
    |> Multi.insert_or_update(
      :upsert,
      session
      |> ChatSession.changeset(%{messages: messages ++ [message]})
    )
    |> Multi.merge(&maybe_increment_msgs_counter/1)
    |> Repo.transaction()
    |> case do
      {:ok, %{upsert: session} = changes} ->
        if Map.has_key?(changes, :inc_counter) do
          {:ok, %{session | msgs_counter: session.msgs_counter + 1}}
        else
          {:ok, session}
        end

      {:error, _operation, changeset, _changes} ->
        {:error, changeset}
    end
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
  @spec query(ChatSession.t(), String.t()) ::
          {:ok, ChatSession.t()}
          | {:error, Ecto.Changeset.t() | :apollo_unavailable}
  def query(session, content) do
    apollo_resp =
      ApolloClient.query(
        content,
        %{expression: session.expression, adaptor: session.adaptor},
        build_history(session)
      )

    case apollo_resp do
      {:ok, %Tesla.Env{status: status, body: body}} when status in 200..299 ->
        message = body["history"] |> Enum.reverse() |> hd()
        save_message(session, message)

      _ ->
        {:error, :apollo_unavailable}
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

  # role sent via async as string
  defp maybe_increment_msgs_counter(%{message: %{"role" => "assistant"}}),
    do: Multi.new()

  defp maybe_increment_msgs_counter(%{message: %{role: :assistant}}),
    do: Multi.new()

  defp maybe_increment_msgs_counter(%{
         upsert: session,
         message: %{"role" => "user"}
       }) do
    maybe_increment_msgs_counter(%{upsert: session, message: %{role: :user}})
  end

  defp maybe_increment_msgs_counter(%{
         upsert: session,
         message: %{role: :user}
       }) do
    Multi.new()
    |> Multi.update_all(
      :inc_counter,
      fn _ ->
        from(cs in ChatSession,
          where: cs.id == ^session.id,
          update: [inc: [msgs_counter: 1]]
        )
      end,
      []
    )
  end
end
