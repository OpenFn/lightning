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
  Requests AI assistance for job-specific tasks with SSE streaming.

  Sends user queries along with job context (expression code and adaptor) to
  Apollo's streaming job_chat endpoint, returning the response body as a lazy
  `Stream` of parsed SSE data strings. Each element is a raw JSON string that
  must be decoded with `Jason.decode!/1`.

  The stream emits Anthropic-formatted events (`content_block_delta`, etc.)
  followed by a final `complete` event containing the full response payload
  (`"history"`, `"usage"`, and `"meta"`).

  ## Options

  - `:context` - Job context including expression code and adaptor info (default: %{})
  - `:history` - Previous conversation messages for context (default: [])
  - `:meta` - Additional metadata like session IDs or user preferences (default: %{})
  - `:metrics_opt_in` - Optional boolean enabling Langfuse metrics tracking
    on the Apollo side. Omitted from the wire payload when not supplied.
  """
  @spec job_chat_stream(String.t(), opts()) :: Tesla.Env.result()
  def job_chat_stream(content, opts \\ []) do
    context = Keyword.get(opts, :context, %{})
    history = Keyword.get(opts, :history, [])
    meta = Keyword.get(opts, :meta, %{})
    metrics_opt_in = Keyword.get(opts, :metrics_opt_in)

    payload =
      %{
        "api_key" => Lightning.Config.apollo(:ai_assistant_api_key),
        "content" => content,
        "context" => context,
        "history" => history,
        "meta" => meta,
        "suggest_code" => true,
        "stream" => true,
        "metrics_opt_in" => metrics_opt_in
      }
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Enum.into(%{})
      |> Jason.encode!()

    stream_client()
    |> Tesla.post("/services/job_chat/stream", payload,
      headers: [{"content-type", "application/json"}],
      opts: [adapter: [response: :stream]]
    )
  end

  @doc """
  Generates or improves workflow templates with SSE streaming.

  Sends requests to Apollo's streaming workflow_chat endpoint to create
  complete workflow YAML definitions from natural language descriptions, or
  to iteratively improve existing workflows based on validation errors or
  user feedback. See `job_chat_stream/2` for details on the stream format;
  the final `complete` event carries `"response"`, `"response_yaml"`, and
  `"usage"`.

  ## Options

  - `:code` - Optional existing workflow YAML to modify or improve
  - `:errors` - Optional validation errors from previous workflow attempts
  - `:history` - Previous conversation messages for context (default: [])
  - `:meta` - Additional metadata (default: %{})
  - `:metrics_opt_in` - Optional boolean enabling Langfuse metrics tracking
    on the Apollo side. Omitted from the wire payload when not supplied.
  """
  @spec workflow_chat_stream(String.t(), opts()) :: Tesla.Env.result()
  def workflow_chat_stream(content, opts \\ []) do
    code = Keyword.get(opts, :code)
    errors = Keyword.get(opts, :errors)
    history = Keyword.get(opts, :history, [])
    meta = Keyword.get(opts, :meta, %{})
    metrics_opt_in = Keyword.get(opts, :metrics_opt_in)

    payload =
      %{
        "api_key" => Lightning.Config.apollo(:ai_assistant_api_key),
        "content" => content,
        "existing_yaml" => code,
        "errors" => errors,
        "history" => history,
        "meta" => meta,
        "stream" => true,
        "metrics_opt_in" => metrics_opt_in
      }
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Enum.into(%{})
      |> Jason.encode!()

    stream_client()
    |> Tesla.post("/services/workflow_chat/stream", payload,
      headers: [{"content-type", "application/json"}],
      opts: [adapter: [response: :stream]]
    )
  end

  @doc """
  Queries the Apollo global chat endpoint with SSE streaming.

  The global chat endpoint unifies job and workflow assistance behind
  an internal router that uses the `page` field to determine context.
  Streaming events (text chunks, changes, status) are emitted as SSE,
  followed by a final `complete` event with the full response payload.

  ## Parameters

  - `content` - User's question or request
  - `opts` - Keyword list of options:
    - `:workflow_yaml` - Full workflow YAML including job bodies (optional)
    - `:page` - Current page URL for routing (optional)
    - `:history` - Previous conversation messages (default: [])
    - `:meta` - Optional metadata map (e.g. session IDs, Langfuse keys).
      Omitted from the wire payload when not supplied.
    - `:metrics_opt_in` - Optional boolean enabling Langfuse metrics tracking
      on the Apollo side. Omitted from the wire payload when not supplied.
  """
  @spec global_chat_stream(String.t(), opts()) :: Tesla.Env.result()
  def global_chat_stream(content, opts \\ []) do
    workflow_yaml = Keyword.get(opts, :workflow_yaml)
    page = Keyword.get(opts, :page)
    history = Keyword.get(opts, :history, [])
    meta = Keyword.get(opts, :meta)
    metrics_opt_in = Keyword.get(opts, :metrics_opt_in)

    payload =
      %{
        "api_key" => Lightning.Config.apollo(:ai_assistant_api_key),
        "content" => content,
        "workflow_yaml" => workflow_yaml,
        "page" => page,
        "history" => history,
        "meta" => meta,
        "metrics_opt_in" => metrics_opt_in,
        "options" => %{"stream" => true}
      }
      |> Enum.reject(fn {_, v} -> is_nil(v) end)
      |> Enum.into(%{})
      |> Jason.encode!()

    stream_client()
    |> Tesla.post("/services/global_chat/stream", payload,
      headers: [{"content-type", "application/json"}],
      opts: [adapter: [response: :stream]]
    )
  end

  defp stream_client do
    # receive_timeout bounds time-to-headers and each gap between SSE
    # chunks, not total stream duration — the MessageProcessor job timeout
    # bounds that.
    timeout = Lightning.Config.apollo(:timeout)

    client_params = [
      {Tesla.Middleware.BaseUrl, Lightning.Config.apollo(:endpoint)},
      Tesla.Middleware.SSE,
      Tesla.Middleware.KeepRequest
    ]

    if match?({Tesla.Adapter.Finch, _}, Application.get_env(:tesla, :adapter)) do
      Tesla.client(
        client_params,
        {Tesla.Adapter.Finch, name: Lightning.Finch, receive_timeout: timeout}
      )
    else
      Tesla.client(client_params)
    end
  end
end
