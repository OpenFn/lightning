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
      :expression,
      :adaptor,
      :history
    ]

    @type t() :: %__MODULE__{
            expression: String.t(),
            adaptor: String.t(),
            history: history()
          }

    @type history() :: [
            %{role: :user | :assistant, content: String.t()}
          ]

    @spec new(String.t(), String.t()) :: t()
    def new(expression, adaptor) do
      %Session{
        expression: expression,
        adaptor: Lightning.AdaptorRegistry.resolve_adaptor(adaptor),
        history: []
      }
    end

    @spec put_history(t(), history() | [%{String.t() => any()}]) :: t()
    def put_history(session, history) do
      %{session | history: history}
    end
  end

  @spec new_session(Job.t()) :: Session.t()
  def new_session(job) do
    Session.new(job.body, job.adaptor)
  end

  @spec query(Session.t(), String.t()) :: Tesla.Env.result()
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
  def endpoint_available?() do
    ApolloClient.test() == :ok
  end
end
