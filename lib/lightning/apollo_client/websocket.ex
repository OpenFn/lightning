defmodule Lightning.ApolloClient.WebSocket do
  @moduledoc """
  WebSocket client for streaming AI responses from Apollo server.

  This module handles the WebSocket connection to Apollo's streaming endpoint,
  processing incoming events and forwarding them to the appropriate channels.
  """
  use WebSockex

  require Logger

  @doc """
  Starts a streaming WebSocket connection to Apollo server.

  ## Parameters

  - `url` - WebSocket URL for Apollo streaming endpoint
  - `payload` - Request payload to send to Apollo

  ## Returns

  - `{:ok, pid}` - WebSocket process started successfully
  - `{:error, reason}` - Failed to establish connection
  """
  def start_stream(url, payload) do
    headers = [
      {"Content-Type", "application/json"},
      {"Authorization", "Bearer #{Lightning.Config.apollo(:ai_assistant_api_key)}"}
    ]

    init_state = %{
      payload: payload,
      lightning_session_id: payload["lightning_session_id"]
    }

    WebSockex.start_link(url, __MODULE__, init_state,
      extra_headers: headers,
      handle_initial_conn_failure: true
    )
  end

  @impl WebSockex
  def handle_connect(_conn, state) do
    Logger.info("[ApolloWebSocket] Connected to Apollo streaming")

    # Send message in Apollo's expected format (without Lightning-specific fields)
    apollo_payload = Map.delete(state.payload, "lightning_session_id")
    message = Jason.encode!(%{
      "event" => "start",
      "data" => apollo_payload
    })

    # Send the message immediately after connecting
    send(self(), {:send_start_message, message})
    {:ok, state}
  end

  @impl WebSockex
  def handle_info({:send_start_message, message}, state) do
    {:reply, {:text, message}, state}
  end

  @impl WebSockex
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, %{"event" => "log", "data" => data}} ->
        Logger.debug("[ApolloWebSocket] Log: #{data}")

      {:ok, %{"event" => "event", "type" => event_type, "data" => data}} ->
        handle_apollo_event(event_type, data, state)

      {:ok, %{"event" => "complete", "data" => data}} ->
        send_to_channel({:apollo_complete, data}, state)

      {:ok, %{"error" => error}} ->
        Logger.error("[ApolloWebSocket] Apollo error: #{inspect(error)}")
        send_to_channel({:apollo_error, error}, state)

      {:error, decode_error} ->
        Logger.error("[ApolloWebSocket] JSON decode error: #{inspect(decode_error)}")

      _ ->
        Logger.warning("[ApolloWebSocket] Unknown message format: #{msg}")
    end

    {:ok, state}
  end

  @impl WebSockex
  def handle_disconnect(disconnect_map, state) do
    Logger.info("[ApolloWebSocket] Disconnected: #{inspect(disconnect_map)}")
    {:ok, state}
  end

  @impl WebSockex
  def handle_cast({:send_message, message}, state) do
    {:reply, {:text, Jason.encode!(message)}, state}
  end

  defp handle_apollo_event(event_type, data, state) do
    Logger.debug("[ApolloWebSocket] Received #{event_type}: #{inspect(data)}")

    case event_type do
      "CHUNK" ->
        send_to_channel({:apollo_event, "CHUNK", data}, state)

      "STATUS" ->
        send_to_channel({:apollo_event, "STATUS", data}, state)

      "COMPLETE" ->
        send_to_channel({:apollo_complete, data}, state)

      "ERROR" ->
        send_to_channel({:apollo_error, data}, state)

      _ ->
        Logger.debug("[ApolloWebSocket] Unknown event type: #{event_type}")
        send_to_channel({:apollo_event, event_type, data}, state)
    end
  end

  defp send_to_channel(message, state) do
    # Broadcast directly to Lightning AI session using the same format as message_status_changed
    if session_id = state.lightning_session_id do
      case message do
        {:apollo_event, "CHUNK", data} ->
          Lightning.broadcast(
            "ai_session:#{session_id}",
            {:ai_assistant, :streaming_chunk, %{content: data, session_id: session_id}}
          )

        {:apollo_event, "STATUS", data} ->
          Lightning.broadcast(
            "ai_session:#{session_id}",
            {:ai_assistant, :status_update, %{status: data, session_id: session_id}}
          )

        {:apollo_complete, _data} ->
          # Mark streaming as complete
          Lightning.broadcast(
            "ai_session:#{session_id}",
            {:ai_assistant, :streaming_complete, %{session_id: session_id}}
          )

        _ ->
          Logger.debug("[ApolloWebSocket] Unhandled message type: #{inspect(message)}")
      end
    end
  end
end