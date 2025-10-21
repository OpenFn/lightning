defmodule Lightning.AiAssistantHelpers do
  require Logger
  import ExUnit.Assertions
  import Eventually

  @apollo_endpoint "http://localhost:4001"

  def stub_online do
    Mox.stub(Lightning.MockConfig, :apollo, fn
      :endpoint -> @apollo_endpoint
      :ai_assistant_api_key -> "ai_assistant_api_key"
      :timeout -> 30_000
    end)

    Mox.stub(Lightning.Tesla.Mock, :call, fn
      %{method: :get, url: @apollo_endpoint <> "/"}, _opts ->
        {:ok, %Tesla.Env{status: 200}}

      %{method: :post} = request, _opts ->
        Logger.warning("""
        Unexpected Tesla HTTP request sent to Apollo (streaming should be used):

        #{inspect(request, pretty: true)}
        """)

        {:error, :unknown}
    end)

    # Stub Finch to prevent actual SSE connections
    # SSEStream will spawn, fail immediately, and streaming simulation will take over
    :ok
  end

  @doc """
  Waits for a chat session to be created and then simulates a streaming response.

  This is useful in tests where you've submitted a form and need to simulate
  the AI response.

  ## Examples

      # For workflow-based assistant:
      submit_and_simulate_stream(workflow_id: workflow.id,
        response: "I'll create your workflow",
        code: valid_yaml
      )

      # For job-based assistant:
      submit_and_simulate_stream(job_id: job.id,
        response: "Here's your answer"
      )
  """
  def submit_and_simulate_stream(opts) when is_list(opts) do
    response = Keyword.get(opts, :response, "AI response")
    code = Keyword.get(opts, :code)
    workflow_id = Keyword.get(opts, :workflow_id)
    job_id = Keyword.get(opts, :job_id)
    timeout = Keyword.get(opts, :timeout, 1000)

    # Drain the ai_assistant Oban queue to execute jobs synchronously
    Oban.drain_queue(Lightning.Oban, queue: :ai_assistant)

    # Get the session based on workflow_id or job_id
    session =
      cond do
        workflow_id ->
          # For workflow template mode (new workflows), check project_id first
          # as sessions are created with project_id not workflow_id
          Lightning.AiAssistant.ChatSession
          |> Lightning.Repo.get_by(project_id: workflow_id) ||
            Lightning.AiAssistant.ChatSession
            |> Lightning.Repo.get_by(workflow_id: workflow_id)

        job_id ->
          Lightning.AiAssistant.ChatSession
          |> Lightning.Repo.get_by(job_id: job_id)

        true ->
          nil
      end

    if session do
      # Subscribe to the session's PubSub topic to wait for completion
      Phoenix.PubSub.subscribe(Lightning.PubSub, "ai_session:#{session.id}")

      simulate_streaming_response(session.id, response, code: code)

      # Wait for the streaming_payload_complete message to arrive
      assert_receive {:ai_assistant, :streaming_payload_complete, _}, timeout

      # Poll until message status is updated in database (indicates LiveView processed it)
      eventually(
        fn ->
          session
          |> Lightning.Repo.reload()
          |> Lightning.Repo.preload(:messages, force: true)
          |> then(& &1.messages)
          |> Enum.any?(fn msg -> msg.status == :success end)
        end,
        true,
        timeout,
        10
      )
    end
  end

  # Backward compatibility: support old function signature
  def submit_and_simulate_stream(workflow_id, opts)
      when is_binary(workflow_id) do
    submit_and_simulate_stream([workflow_id: workflow_id] ++ opts)
  end

  @doc """
  Simulates SSE streaming by broadcasting events directly via PubSub.

  This mocks the behavior of Lightning.ApolloClient.SSEStream without
  actually making HTTP requests to Apollo.

  Note: This function broadcasts messages but does not wait for them to be processed.
  Use submit_and_simulate_stream/1 which includes synchronization.
  """
  def simulate_streaming_response(session_id, content, opts \\ []) do
    code = Keyword.get(opts, :code)

    # Broadcast thinking status
    Lightning.broadcast(
      "ai_session:#{session_id}",
      {:ai_assistant, :status_update,
       %{
         status: "Analyzing your request...",
         session_id: session_id
       }}
    )

    # Broadcast content chunks
    words = String.split(content, " ")

    words
    |> Enum.with_index()
    |> Enum.each(fn {word, index} ->
      # Add space after each word except the last one
      chunk = if index < length(words) - 1, do: word <> " ", else: word

      Lightning.broadcast(
        "ai_session:#{session_id}",
        {:ai_assistant, :streaming_chunk,
         %{
           content: chunk,
           session_id: session_id
         }}
      )
    end)

    # Broadcast completion
    Lightning.broadcast(
      "ai_session:#{session_id}",
      {:ai_assistant, :streaming_complete, %{session_id: session_id}}
    )

    # Broadcast payload with usage and code
    payload_data = %{
      session_id: session_id,
      usage: %{"input_tokens" => 100, "output_tokens" => 50},
      meta: %{},
      code: code
    }

    Lightning.broadcast(
      "ai_session:#{session_id}",
      {:ai_assistant, :streaming_payload_complete, payload_data}
    )
  end

  @doc """
  Simulates a streaming error by broadcasting an error event via PubSub.

  This mocks error scenarios from Apollo without making actual HTTP requests.

  Note: This function broadcasts the error but does not wait for it to be processed.
  Use submit_and_simulate_error/1 which includes synchronization.
  """
  def simulate_streaming_error(session_id, error_message) do
    # Broadcast error
    Lightning.broadcast(
      "ai_session:#{session_id}",
      {:ai_assistant, :streaming_error,
       %{
         session_id: session_id,
         error: error_message
       }}
    )
  end

  @doc """
  Waits for a chat session to be created and then simulates a streaming error.

  This is useful in tests where you've submitted a form and need to simulate
  an AI error response.
  """
  def submit_and_simulate_error(opts) when is_list(opts) do
    error_message =
      Keyword.get(opts, :error, "An error occurred")

    workflow_id = Keyword.get(opts, :workflow_id)
    job_id = Keyword.get(opts, :job_id)
    timeout = Keyword.get(opts, :timeout, 1000)

    # Drain the ai_assistant Oban queue to execute jobs synchronously
    Oban.drain_queue(Lightning.Oban, queue: :ai_assistant)

    # Get the session based on workflow_id or job_id
    session =
      cond do
        workflow_id ->
          # For workflow template mode (new workflows), check project_id first
          # as sessions are created with project_id not workflow_id
          Lightning.AiAssistant.ChatSession
          |> Lightning.Repo.get_by(project_id: workflow_id) ||
            Lightning.AiAssistant.ChatSession
            |> Lightning.Repo.get_by(workflow_id: workflow_id)

        job_id ->
          Lightning.AiAssistant.ChatSession
          |> Lightning.Repo.get_by(job_id: job_id)

        true ->
          nil
      end

    if session do
      # Subscribe to the session's PubSub topic to wait for the error
      Phoenix.PubSub.subscribe(Lightning.PubSub, "ai_session:#{session.id}")

      simulate_streaming_error(session.id, error_message)

      # Wait for the streaming_error message to arrive
      assert_receive {:ai_assistant, :streaming_error, _}, timeout

      # Poll until message status is updated in database (indicates LiveView processed it)
      eventually(
        fn ->
          session
          |> Lightning.Repo.reload()
          |> Lightning.Repo.preload(:messages, force: true)
          |> then(& &1.messages)
          |> Enum.any?(fn msg -> msg.status == :error end)
        end,
        true,
        timeout,
        10
      )
    end
  end
end
