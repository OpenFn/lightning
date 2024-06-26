defmodule Lightning.AiAssistant do
  @moduledoc """
  The AI assistant module.
  """

  alias Lightning.Accounts.User
  alias Lightning.ApolloClient
  alias Lightning.Workflows.Job

  defmodule Session do
    @moduledoc """
    Represents a session with the AI assistant.
    """

    defstruct [
      :id,
      :expression,
      :adaptor,
      :history
    ]

    @type t() :: %__MODULE__{
            id: Ecto.UUID.t(),
            expression: String.t(),
            adaptor: String.t(),
            history: history()
          }

    @type history() :: [
            %{role: :user | :assistant, content: String.t()}
          ]

    @spec new(Job.t()) :: t()
    def new(job) do
      %Session{
        id: job.id,
        expression: job.body,
        adaptor: Lightning.AdaptorRegistry.resolve_adaptor(job.adaptor),
        history: []
      }
    end

    @spec put_history(t(), history() | [%{String.t() => any()}]) :: t()
    def put_history(session, history) do
      history =
        Enum.map(history, fn h ->
          %{role: h["role"] || h[:role], content: h["content"] || h[:content]}
        end)

      %{session | history: history}
    end

    @spec push_history(t(), %{String.t() => any()}) :: t()
    def push_history(session, message) do
      history =
        session.history ++
          [
            %{
              role: message["role"] || message[:role],
              content: message["content"] || message[:content]
            }
          ]

      %{session | history: history}
    end

    @doc """
    Puts the given expression into the session.
    """
    @spec put_expression(t(), String.t()) :: t()
    def put_expression(session, expression) do
      %{session | expression: expression}
    end
  end

  @doc """
  Creates a new session with the given job.

  **Example**

      iex> AiAssistant.new_session(%Lightning.Workflows.Job{
      ...>   body: "fn()",
      ...>   adaptor: "@openfn/language-common@latest"
      ...> })
      %Lightning.AiAssistant.Session{
        expression: "fn()",
        adaptor: "@openfn/language-common@1.6.2",
        history: []
      }

  > ℹ️ The `adaptor` field is resolved to the latest version when `@latest`
  > is provided as Apollo expects a specific version.
  """

  @spec new_session(Job.t()) :: Session.t()
  def new_session(job) do
    Session.new(job)
  end

  @spec push_history(Session.t(), %{String.t() => any()}) :: Session.t()
  def push_history(session, message) do
    Session.push_history(session, message)
  end

  @doc """
  Queries the AI assistant with the given content.

  Returns `{:ok, session}` if the query was successful, otherwise `:error`.

  **Example**

      iex> AiAssistant.query(session, "fn()")
      {:ok, session}
  """
  @spec query(Session.t(), String.t()) :: {:ok, Session.t()} | :error
  def query(session, content) do
    ApolloClient.query(
      content,
      %{expression: session.expression, adaptor: session.adaptor},
      session.history
    )
    |> case do
      {:ok, %Tesla.Env{status: status} = response} when status in 200..299 ->
        {:ok, session |> Session.put_history(response.body["history"])}

      _ ->
        :error
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
