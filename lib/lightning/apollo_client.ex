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

  # Keep existing query function for backward compatibility
  @spec query(String.t(), context(), list(), map()) :: Tesla.Env.result()
  def query(content, context \\ %{}, history \\ [], meta \\ %{}) do
    # Call the renamed implementation
    job_chat(content, context, history, meta)
  end

  @doc """
  Sends a request to the job_chat service to get AI assistance with job code.

  Returns a tuple containing {:ok, response} or {:error, reason}.
  """
  @spec job_chat(String.t(), context(), list(), map()) :: Tesla.Env.result()
  def job_chat(content, context \\ %{}, history \\ [], meta \\ %{}) do
    payload = %{
      "api_key" => Lightning.Config.apollo(:ai_assistant_api_key),
      "content" => content,
      "context" => context,
      "history" => history,
      "meta" => meta
    }

    client() |> Tesla.post("/services/job_chat", payload)
  end

  @doc """
  Sends a request to the workflow_chat service to generate or improve workflow YAML.

  Returns a tuple containing {:ok, response} or {:error, reason}.

  The response contains text and YAML when successful.
  """
  @spec workflow_chat(
          String.t(),
          String.t() | nil,
          String.t() | nil,
          list(),
          map()
        ) :: Tesla.Env.result()
  def workflow_chat(
        content,
        existing_yaml \\ nil,
        errors \\ nil,
        history \\ [],
        meta \\ %{}
      ) do
    payload =
      %{
        "api_key" => Lightning.Config.apollo(:ai_assistant_api_key),
        "content" => content,
        "existing_yaml" => existing_yaml,
        "errors" => errors,
        "history" => history,
        "meta" => meta
      }
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Enum.into(%{})

    client() |> Tesla.post("/services/workflow_chat", payload)
  end

  @doc """
  Checks if the Apollo endpoint is available.
  """
  @spec test() :: :ok | :error
  def test do
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
