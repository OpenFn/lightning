defmodule Lightning.ApolloClient do
  @moduledoc """
  HTTP client for communicating with the Apollo AI service.

  This module provides a Tesla-based HTTP client for interacting with Apollo,
  an external AI service that powers Lightning's intelligent assistance features.
  Apollo offers two main AI services:

  1. **Job Chat** - Provides AI assistance for coding tasks, debugging, and
     adaptor-specific guidance within individual workflow jobs
  2. **Workflow Chat** - Generates complete workflow templates from natural
     language descriptions

  ## Configuration

  The Apollo client requires the following configuration values:
  - `:endpoint` - Base URL of the Apollo service
  - `:ai_assistant_api_key` - Authentication key for API access
  """

  @typedoc """
  Context information for job-specific AI assistance.

  Contains the job's expression code and adaptor information to help the AI
  provide more targeted and relevant assistance.
  """
  @type context() ::
          %{
            expression: String.t(),
            adaptor: String.t()
          }
          | %{}

  @type opts :: keyword()

  @doc """
  Performs a health check on the Apollo service endpoint.

  Sends a GET request to the root endpoint to verify the service is running
  and accessible. This should be called before attempting AI operations to
  ensure graceful degradation when the service is unavailable.

  ## Returns

  - `:ok` - Service responded with 2xx status code
  - `:error` - Service unavailable, network error, or non-2xx response
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

  @doc """
  Requests AI assistance for job-specific coding tasks and debugging.

  Sends user queries along with job context (expression code and adaptor) to the
  Apollo job_chat service. The AI provides targeted assistance for coding tasks,
  error debugging, adaptor-specific guidance, and best practices.

  ## Parameters

  - `content` - User's question or request for assistance
  - `opts` - Keyword list of options:
    - `:context` - Job context including expression code and adaptor info (default: %{})
    - `:history` - Previous conversation messages for context (default: [])
    - `:meta` - Additional metadata like session IDs or user preferences (default: %{})

  ## Returns

  `Tesla.Env.result()` with response body containing:
  - `"history"` - Updated conversation including AI response
  - `"usage"` - Token usage and cost information
  - `"meta"` - Updated metadata
  """
  @spec job_chat(String.t(), opts()) :: Tesla.Env.result()
  def job_chat(content, opts \\ []) do
    context = Keyword.get(opts, :context, %{})
    history = Keyword.get(opts, :history, [])
    meta = Keyword.get(opts, :meta, %{})

    payload = %{
      "api_key" => Lightning.Config.apollo(:ai_assistant_api_key),
      "content" => content,
      "context" => context,
      "history" => history,
      "meta" => meta
    }

    client()
    |> Tesla.post("/services/job_chat", payload)
  end

  @doc """
  Generates or improves workflow templates using AI assistance.

  Sends requests to the Apollo workflow_chat service to create complete workflow
  YAML definitions from natural language descriptions. Can also iteratively improve
  existing workflows based on validation errors or user feedback.

  ## Parameters

  - `content` - Natural language description of desired workflow functionality
  - `opts` - Keyword list of options:
    - `:code` - Optional existing workflow YAML to modify or improve
    - `:errors` - Optional validation errors from previous workflow attempts
    - `:history` - Previous conversation messages for context (default: [])
    - `:meta` - Additional metadata (default: %{})

  ## Returns

  `Tesla.Env.result()` with response body containing:
  - `"response"` - Human-readable explanation of the generated workflow
  - `"response_yaml"` - Complete workflow YAML definition
  - `"usage"` - Token usage and cost information
  """
  @spec workflow_chat(String.t(), opts()) :: Tesla.Env.result()
  def workflow_chat(content, opts \\ []) do
    code = Keyword.get(opts, :code)
    errors = Keyword.get(opts, :errors)
    history = Keyword.get(opts, :history, [])
    meta = Keyword.get(opts, :meta, %{})

    payload =
      %{
        "api_key" => Lightning.Config.apollo(:ai_assistant_api_key),
        "content" => content,
        "existing_yaml" => code,
        "errors" => errors,
        "history" => history,
        "meta" => meta
      }
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Enum.into(%{})

    client() |> Tesla.post("/services/workflow_chat", payload)
  end

  defp client do
    client_params = [
      {Tesla.Middleware.BaseUrl, Lightning.Config.apollo(:endpoint)},
      Tesla.Middleware.JSON,
      Tesla.Middleware.KeepRequest
    ]

    if match?({Tesla.Adapter.Finch, _}, Application.get_env(:tesla, :adapter)) do
      Tesla.client(
        client_params,
        {Tesla.Adapter.Finch,
         name: Lightning.Finch,
         receive_timeout: Lightning.Config.apollo(:timeout)}
      )
    else
      Tesla.client(client_params)
    end
  end
end
