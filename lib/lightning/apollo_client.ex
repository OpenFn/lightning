defmodule Lightning.ApolloClient do
  @moduledoc """
  Client for communicating with the Apollo service.
  """
  @type context() ::
          %{
            expression: String.t(),
            adaptor: String.t()
          }
          | %{}

  @spec query(String.t(), context(), list()) :: Tesla.Env.result()
  def query(content, context \\ %{}, history \\ []) do
    payload = %{
      "api_key" => Lightning.Config.apollo(:openai_api_key),
      "content" => content,
      "context" => context,
      "history" => history
    }

    client() |> Tesla.post("/services/job_chat", payload)
  end

  @doc """
  Checks if the Apollo endpoint is available.
  """
  @spec test() :: :ok | :error
  def test() do
    client()
    |> Tesla.get("/")
    |> case do
      {:ok, %{status: status}} when status in 200..299 -> :ok
      _ -> :error
    end
  end

  defp client do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, Lightning.Config.apollo(:endpoint)},
      Tesla.Middleware.JSON,
      Tesla.Middleware.KeepRequest
    ])
  end
end
