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

  defp client do
    Tesla.client([
      {Tesla.Middleware.BaseUrl, Lightning.Config.apollo(:endpoint)},
      Tesla.Middleware.JSON,
      Tesla.Middleware.KeepRequest
    ])
  end
end
