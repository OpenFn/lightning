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

    apollo_timeout = Lightning.Config.apollo(:timeout) || 30_000
    stream_timeout = apollo_timeout + 10_000

    timeout_ref = Process.send_after(self(), :stream_timeout, stream_timeout)

    parent = self()

    spawn_link(fn ->
      stream_request(url, apollo_payload, parent, lightning_session_id)
    end)

    {:ok,
     %{
       session_id: lightning_session_id,
       timeout_ref: timeout_ref,
       completed: false
     }}
  end

  @impl GenServer
  def handle_info({:sse_event, event_type, data}, state) do
    handle_sse_event(event_type, data, state)
    {:noreply, state}
  end

  def handle_info(:stream_timeout, %{completed: false} = state) do
    Logger.error("[SSEStream] Stream timeout for session #{state.session_id}")
    broadcast_error(state.session_id, "Request timed out. Please try again.")
    {:stop, :timeout, state}
  end

  def handle_info(:stream_timeout, state) do
    {:noreply, state}
  end

  def handle_info({:sse_complete}, state) do
    if state.timeout_ref, do: Process.cancel_timer(state.timeout_ref)
    Logger.info("[SSEStream] Stream completed for session #{state.session_id}")
    {:stop, :normal, %{state | completed: true}}
  end

  def handle_info({:sse_error, reason}, state) do
    if state.timeout_ref, do: Process.cancel_timer(state.timeout_ref)

    Logger.error(
      "[SSEStream] Stream error for session #{state.session_id}: #{inspect(reason)}"
    )

    error_message =
      case reason do
        :timeout -> "Connection timed out"
        :closed -> "Connection closed unexpectedly"
        {:shutdown, _} -> "Server shut down"
        {:http_error, status} -> "Server returned error status #{status}"
        _ -> "Connection error: #{inspect(reason)}"
      end

    broadcast_error(state.session_id, error_message)
    {:stop, :normal, %{state | completed: true}}
  end

  defp stream_request(url, payload, parent, session_id) do
    Logger.info("[SSEStream] Starting SSE connection to #{url}")
    Logger.debug("[SSEStream] Payload: #{inspect(payload)}")

    headers = [
      {"Content-Type", "application/json"},
      {"Accept", "text/event-stream"},
      {"Authorization",
       "Bearer #{Lightning.Config.apollo(:ai_assistant_api_key)}"}
    ]

    case Finch.build(:post, url, headers, Jason.encode!(payload))
         |> Finch.stream(Lightning.Finch, %{}, fn
           {:status, status}, acc ->
             Logger.debug("[SSEStream] Response status: #{status}")

             if status >= 400 do
               send(parent, {:sse_error, {:http_error, status}})
             end

             Map.put(acc, :status, status)

           {:headers, headers}, acc ->
             Logger.debug("[SSEStream] Response headers: #{inspect(headers)}")
             acc

           {:data, chunk}, acc ->
             Logger.debug("[SSEStream] Raw chunk received: #{inspect(chunk)}")

             if Map.get(acc, :status, 200) in 200..299 do
               parse_sse_chunk(chunk, parent, session_id)
             end

             acc
         end) do
      {:ok, %{status: status}} when status in 200..299 ->
        Logger.info("[SSEStream] Stream completed successfully")
        send(parent, {:sse_complete})

      {:ok, %{status: status}} ->
        Logger.error("[SSEStream] Stream failed with status: #{status}")
        send(parent, {:sse_error, {:http_error, status}})

      {:error, reason, _acc} ->
        Logger.error(
          "[SSEStream] Stream failed before response: #{inspect(reason)}"
        )

        send(parent, {:sse_error, reason})
    end
  end

  defp parse_sse_chunk(chunk, parent, _session_id) do
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

        (line == "" and acc.event) && acc.data ->
          send(parent, {:sse_event, acc.event, acc.data})
          %{event: nil, data: nil}

        true ->
          acc
      end
    end)
  end

  defp handle_sse_event(event_type, data, state) do
    case event_type do
      "content_block_delta" ->
        handle_content_block_delta(data, state.session_id)

      "message_stop" ->
        Logger.debug("[SSEStream] Received message_stop, broadcasting complete")
        broadcast_complete(state.session_id)

      "complete" ->
        handle_complete_event(data, state.session_id)

      "error" ->
        handle_error_event(data, state.session_id)

      "log" ->
        Logger.debug("[SSEStream] Apollo log: #{inspect(data)}")

      _ ->
        Logger.debug("[SSEStream] Unhandled event type: #{event_type}")
        :ok
    end
  end

  defp handle_content_block_delta(data, session_id) do
    case Jason.decode(data) do
      {:ok, %{"delta" => %{"type" => "text_delta", "text" => text}}} ->
        Logger.debug("[SSEStream] Broadcasting chunk: #{inspect(text)}")
        broadcast_chunk(session_id, text)

      {:ok, %{"delta" => %{"type" => "thinking_delta", "thinking" => thinking}}} ->
        Logger.debug("[SSEStream] Broadcasting status: #{inspect(thinking)}")
        broadcast_status(session_id, thinking)

      _ ->
        :ok
    end
  end

  defp handle_complete_event(data, session_id) do
    Logger.debug("[SSEStream] Received complete event with payload")

    case Jason.decode(data) do
      {:ok, payload} ->
        Logger.debug(
          "[SSEStream] Broadcasting complete payload: #{inspect(Map.keys(payload))}"
        )

        broadcast_payload_complete(session_id, payload)

      {:error, error} ->
        Logger.error(
          "[SSEStream] Failed to parse complete event payload: #{inspect(error)}"
        )
    end

    :ok
  end

  defp handle_error_event(data, session_id) do
    Logger.error("[SSEStream] Received error event: #{inspect(data)}")

    error_message =
      case Jason.decode(data) do
        {:ok, %{"message" => msg}} -> msg
        {:ok, %{"error" => err}} -> err
        _ -> "An error occurred while streaming"
      end

    broadcast_error(session_id, error_message)
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

  defp broadcast_error(session_id, error_message) do
    payload_data = %{
      session_id: session_id,
      error: error_message
    }

    Lightning.broadcast(
      "ai_session:#{session_id}",
      {:ai_assistant, :streaming_error, payload_data}
    )
  end
end
