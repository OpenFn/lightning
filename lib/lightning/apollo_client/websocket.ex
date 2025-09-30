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

    init_state = %{payload: payload}

    WebSockex.start_link(url, __MODULE__, init_state,
      extra_headers: headers,
      handle_initial_conn_failure: true
    )
  end

  @impl WebSockex
  def handle_connect(_conn, state) do
    Logger.info("[ApolloWebSocket] Connected to Apollo streaming")

    # Send initial payload
    message = Jason.encode!(state.payload)
    {:reply, {:text, message}, state}
  end

  @impl WebSockex
  def handle_frame({:text, msg}, state) do
    case Jason.decode(msg) do
      {:ok, %{"event" => event_type, "data" => data}} ->
        handle_apollo_event(event_type, data, state)

      {:ok, %{"type" => event_type, "data" => data}} ->
        handle_apollo_event(event_type, data, state)

      {:ok, %{"error" => error}} ->
        Logger.error("[ApolloWebSocket] Apollo error: #{inspect(error)}")
        send_to_channel({:apollo_error, error}, state)

      {:error, decode_error} ->
        Logger.error("[ApolloWebSocket] JSON decode error: #{inspect(decode_error)}")

      _ ->
        Logger.warn("[ApolloWebSocket] Unknown message format: #{msg}")
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

  defp send_to_channel(message, _state) do
    # Broadcast to all connected ApolloChannel processes
    Phoenix.PubSub.broadcast(
      Lightning.PubSub,
      "apollo:events",
      message
    )
  end
end