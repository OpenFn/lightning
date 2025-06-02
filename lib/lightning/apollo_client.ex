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

  ## Usage Examples

      # Check service availability
      case ApolloClient.test() do
        :ok -> # Service is healthy
        :error -> # Service unavailable
      end

      # Get job assistance
      {:ok, response} = ApolloClient.job_chat(
        "How do I handle API rate limits?",
        %{expression: "fn() => http.get('/api/data')", adaptor: "@openfn/language-http"},
        previous_messages,
        %{session_id: "123"}
      )

      # Generate workflow template
      {:ok, response} = ApolloClient.workflow_chat(
        "Create a daily sync from Salesforce to PostgreSQL",
        nil,
        nil,
        [],
        %{}
      )
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

  @doc """
  Performs a health check on the Apollo service endpoint.

  Sends a GET request to the root endpoint to verify the service is running
  and accessible. This should be called before attempting AI operations to
  ensure graceful degradation when the service is unavailable.

  ## Returns

  - `:ok` - Service responded with 2xx status code
  - `:error` - Service unavailable, network error, or non-2xx response

  ## Examples

      case ApolloClient.test() do
        :ok ->
          # Service is healthy, proceed with AI operations
          show_ai_features()
        :error ->
          # Service unavailable, disable AI features
          hide_ai_features()
      end

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
  - `context` - Job context including expression code and adaptor info
  - `history` - Previous conversation messages for context (list of maps with `:role` and `:content`)
  - `meta` - Additional metadata like session IDs or user preferences

  ## Returns

  `Tesla.Env.result()` with response body containing:
  - `"history"` - Updated conversation including AI response
  - `"usage"` - Token usage and cost information
  - `"meta"` - Updated metadata

  ## Examples

      # Basic job assistance
      {:ok, %{body: %{"history" => updated_history}}} = ApolloClient.job_chat(
        "Why is my HTTP request returning a 401 error?",
        %{
          expression: "fn(state) => http.get('https://api.example.com/data', {headers: {'Authorization': 'Bearer ' + state.token}})",
          adaptor: "@openfn/language-http"
        }
      )

      # With conversation history
      {:ok, response} = ApolloClient.job_chat(
        "Can you show me how to add error handling?",
        job_context,
        [
          %{role: "user", content: "How do I make an HTTP request?"},
          %{role: "assistant", content: "Here's how to make HTTP requests..."}
        ],
        %{session_id: session.id}
      )
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

    client()
    |> Tesla.post("/services/job_chat", payload)
  end

  @doc """
  Legacy alias for `job_chat/4` maintained for backward compatibility.

  ## Deprecated

  Use `job_chat/4` instead. This function will be removed in a future version.

  ## Parameters

  Same as `job_chat/4`.

  ## Examples

      # Old way (deprecated)
      {:ok, response} = ApolloClient.query(content, context, history, meta)

      # New way (preferred)
      {:ok, response} = ApolloClient.job_chat(content, context, history, meta)

  """
  @spec query(String.t(), context(), list(), map()) :: Tesla.Env.result()
  def query(content, context \\ %{}, history \\ [], meta \\ %{}) do
    job_chat(content, context, history, meta)
  end

  @doc """
  Generates or improves workflow templates using AI assistance.

  Sends requests to the Apollo workflow_chat service to create complete workflow
  YAML definitions from natural language descriptions. Can also iteratively improve
  existing workflows based on validation errors or user feedback.

  ## Parameters

  - `content` - Natural language description of desired workflow functionality
  - `existing_yaml` - Optional existing workflow YAML to modify or improve
  - `errors` - Optional validation errors from previous workflow attempts
  - `history` - Previous conversation messages for context
  - `meta` - Additional metadata

  ## Returns

  `Tesla.Env.result()` with response body containing:
  - `"response"` - Human-readable explanation of the generated workflow
  - `"response_yaml"` - Complete workflow YAML definition
  - `"usage"` - Token usage and cost information

  ## Examples

      # Generate new workflow from description
      {:ok, %{body: %{"response_yaml" => yaml}}} = ApolloClient.workflow_chat(
        "Create a daily workflow that syncs Salesforce contacts to a PostgreSQL database"
      )

      # Improve existing workflow
      {:ok, response} = ApolloClient.workflow_chat(
        "Add error handling and logging to this workflow",
        existing_workflow_yaml
      )

      # Fix validation errors
      {:ok, response} = ApolloClient.workflow_chat(
        "Please fix the validation errors in this workflow",
        broken_yaml,
        "Invalid cron expression: '0 0 * * 8'. Day of week must be 0-6."
      )

      # With conversation context
      {:ok, response} = ApolloClient.workflow_chat(
        "Make the sync run every 2 hours instead of daily",
        current_yaml,
        nil,
        previous_conversation,
        %{project_id: project.id}
      )
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

  defp client do
    client_params = [
        {Tesla.Middleware.BaseUrl, Lightning.Config.apollo(:endpoint)},
        Tesla.Middleware.JSON,
        Tesla.Middleware.KeepRequest
      ]

    if match?({Tesla.Adapter.Finch, _}, Application.get_env(:tesla, :adapter)) do
      Tesla.client(client_params,
        {Tesla.Adapter.Finch,
        name: Lightning.Finch, receive_timeout: Lightning.Config.apollo(:timeout)}
      )
    else
      Tesla.client(client_params)
    end
  end
end
