defmodule Lightning.ApolloClient.SSEStream do
  @moduledoc """
  Server-Sent Events (SSE) client for streaming AI responses from Apollo server.

  This module handles HTTP streaming connections to Apollo's SSE endpoints,
  parsing incoming events and forwarding them to the appropriate channels.
  """
  use GenServer

  require Logger

  @doc """
  Starts a streaming SSE connection to Apollo server.

  ## Parameters

  - `url` - HTTP URL for Apollo streaming endpoint
  - `payload` - Request payload to send to Apollo

  ## Returns

  - `{:ok, pid}` - SSE stream process started successfully
  - `{:error, reason}` - Failed to establish connection
  """
  def start_stream(url, payload) do
    GenServer.start_link(__MODULE__, {url, payload})
  end

  @impl GenServer
  def init({url, payload}) do
    lightning_session_id = payload["lightning_session_id"]
    apollo_payload = Map.delete(payload, "lightning_session_id")

    # Start the HTTP streaming request in a separate process
    parent = self()

    spawn_link(fn ->
      stream_request(url, apollo_payload, parent, lightning_session_id)
    end)

    {:ok, %{session_id: lightning_session_id}}
  end

  @impl GenServer
  def handle_info({:sse_event, event_type, data}, state) do
    handle_sse_event(event_type, data, state)
    {:noreply, state}
  end

  def handle_info({:sse_complete}, state) do
    Logger.info("[SSEStream] Stream completed for session #{state.session_id}")
    {:stop, :normal, state}
  end

  def handle_info({:sse_error, reason}, state) do
    Logger.error("[SSEStream] Stream error for session #{state.session_id}: #{inspect(reason)}")
    {:stop, :normal, state}
  end

  defp stream_request(url, payload, parent, session_id) do
    Logger.info("[SSEStream] Starting SSE connection to #{url}")
    Logger.info("[SSEStream] Payload: #{inspect(payload)}")

    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "text/event-stream"},
      {"Authorization", "Bearer #{Lightning.Config.apollo(:ai_assistant_api_key)}"}
    ]

    body = Jason.encode!(payload)

    # Use Finch for streaming HTTP requests
    request = Finch.build(:post, url, headers, body)

    case Finch.stream(request, Lightning.Finch, nil, fn
      {:status, status}, acc ->
        Logger.info("[SSEStream] Response status: #{status}")
        acc

      {:headers, headers}, acc ->
        Logger.info("[SSEStream] Response headers: #{inspect(headers)}")
        acc

      {:data, chunk}, acc ->
        Logger.info("[SSEStream] Raw chunk received: #{inspect(chunk)}")
        parse_sse_chunk(chunk, parent, session_id)
        acc

    end) do
      {:ok, _acc} ->
        Logger.info("[SSEStream] Stream completed successfully")
        send(parent, {:sse_complete})

      {:error, reason} ->
        Logger.error("[SSEStream] Stream failed: #{inspect(reason)}")
        send(parent, {:sse_error, reason})
    end
  end

  defp parse_sse_chunk(chunk, parent, _session_id) do
    # SSE format:
    # event: CHUNK
    # data: {"content": "hello"}
    #
    # (blank line)

    chunk
    |> String.split("\n")
    |> Enum.reduce(%{event: nil, data: nil}, fn line, acc ->
      cond do
        String.starts_with?(line, "event:") ->
          event = line |> String.trim_leading("event:") |> String.trim()
          %{acc | event: event}

        String.starts_with?(line, "data:") ->
          data = line |> String.trim_leading("data:") |> String.trim()
          %{acc | data: data}

        line == "" and acc.event && acc.data ->
          # Complete event, send it
          send(parent, {:sse_event, acc.event, acc.data})
          %{event: nil, data: nil}

        true ->
          acc
      end
    end)
  end

  defp handle_sse_event(event_type, data, state) do
    session_id = state.session_id

    case event_type do
      "content_block_delta" ->
        # Parse the Anthropic streaming event
        case Jason.decode(data) do
          {:ok, %{"delta" => %{"type" => "text_delta", "text" => text}}} ->
            Logger.info("[SSEStream] Broadcasting chunk: #{inspect(text)}")
            broadcast_chunk(session_id, text)

          {:ok, %{"delta" => %{"type" => "thinking_delta", "thinking" => thinking}}} ->
            Logger.info("[SSEStream] Broadcasting status: #{inspect(thinking)}")
            broadcast_status(session_id, thinking)

          _ ->
            :ok
        end

      "message_stop" ->
        Logger.info("[SSEStream] Received message_stop, broadcasting complete")
        broadcast_complete(session_id)

      "complete" ->
        Logger.info("[SSEStream] Received complete event with payload")
        # Parse and broadcast the complete payload with usage, meta, and code
        case Jason.decode(data) do
          {:ok, payload} ->
            Logger.info("[SSEStream] Broadcasting complete payload: #{inspect(Map.keys(payload))}")
            broadcast_payload_complete(session_id, payload)

          {:error, error} ->
            Logger.error("[SSEStream] Failed to parse complete event payload: #{inspect(error)}")
        end

        :ok

      "error" ->
        Logger.error("[SSEStream] Received error event: #{inspect(data)}")

      "log" ->
        # Just log messages from Apollo, don't broadcast
        Logger.debug("[SSEStream] Apollo log: #{inspect(data)}")

      _ ->
        Logger.debug("[SSEStream] Unhandled event type: #{event_type}")
        :ok
    end
  end

  defp broadcast_chunk(session_id, data) do
    Lightning.broadcast(
      "ai_session:#{session_id}",
      {:ai_assistant, :streaming_chunk, %{content: data, session_id: session_id}}
    )
  end

  defp broadcast_status(session_id, data) do
    Lightning.broadcast(
      "ai_session:#{session_id}",
      {:ai_assistant, :status_update, %{status: data, session_id: session_id}}
    )
  end

  defp broadcast_complete(session_id) do
    Lightning.broadcast(
      "ai_session:#{session_id}",
      {:ai_assistant, :streaming_complete, %{session_id: session_id}}
    )
  end

  defp broadcast_payload_complete(session_id, payload) do
    # Extract relevant fields from the complete payload
    # For job_chat: payload has "usage", "meta"
    # For workflow_chat: payload has "usage", "meta", "response_yaml"
    payload_data = %{
      session_id: session_id,
      usage: Map.get(payload, "usage"),
      meta: Map.get(payload, "meta"),
      code: Map.get(payload, "response_yaml")
    }

    Lightning.broadcast(
      "ai_session:#{session_id}",
      {:ai_assistant, :streaming_payload_complete, payload_data}
    )
  end
end
