
defmodule LightningWeb.ApolloChannel do
  @moduledoc """
  Websocket channel to handle streaming AI responses from Apollo server.
  """
  use LightningWeb, :channel

  require Logger

  @impl true
  def handle_info({:apollo_log, data}, socket) do
    push(socket, "log", %{data: data})
    {:noreply, socket}
  end

  def handle_info({:apollo_event, type, data}, socket) do
    session_id = socket.assigns[:session_id]

    case type do
      "CHUNK" ->
        push(socket, "chunk", %{data: data})
        if session_id, do: broadcast_chunk_to_ui(session_id, data)

      "STATUS" ->
        push(socket, "status", %{data: data})
        if session_id, do: broadcast_status_to_ui(session_id, data)

      _ ->
        push(socket, "event", %{type: type, data: data})
    end
    {:noreply, socket}
  end

  def handle_info({:apollo_complete, data}, socket) do
    push(socket, "complete", %{data: data})
    {:noreply, socket}
  end

  def handle_info({:apollo_error, error}, socket) do
    push(socket, "error", %{message: error})
    {:noreply, socket}
  end

  @impl true
  def join("apollo:stream", _payload, socket) do
    # Subscribe to Apollo WebSocket events
    Phoenix.PubSub.subscribe(Lightning.PubSub, "apollo:events")
    {:ok, socket}
  end

  @impl true
  def handle_in("stream_request", payload, socket) do
    # Forward the request to Apollo server and start streaming
    case start_apollo_stream(payload) do
      {:ok, stream_ref} ->
        {:reply, {:ok, %{stream_id: stream_ref}}, assign(socket, stream_ref: stream_ref)}

      {:error, reason} ->
        {:reply, {:error, %{reason: reason}}, socket}
    end
  end

  def handle_in("chunk", %{"data" => data}, socket) do
    push(socket, "chunk", %{data: data})
    {:noreply, socket}
  end

  def handle_in("status", %{"message" => message}, socket) do
    push(socket, "status", %{message: message})
    {:noreply, socket}
  end

  def handle_in("response", %{"payload" => payload}, socket) do
    push(socket, "response", %{payload: payload})
    {:noreply, socket}
  end

  @impl true
  def terminate(_reason, _socket) do
    # Clean up any active streams if needed
    :ok
  end

  defp start_apollo_stream(payload) do
    apollo_ws_url = get_apollo_ws_url()

    case Lightning.ApolloClient.WebSocket.start_stream(apollo_ws_url, payload) do
      {:ok, pid} ->
        # Store pid for cleanup
        stream_ref = :erlang.phash2(pid) |> Integer.to_string()
        {:ok, stream_ref}

      {:error, reason} ->
        Logger.error("[ApolloChannel] Failed to start Apollo WebSocket: #{inspect(reason)}")
        {:error, reason}
    end
  end

  defp get_apollo_ws_url do
    base_url = Lightning.Config.apollo(:endpoint)
    # Convert HTTP(S) to WS(S)
    base_url
    |> String.replace("https://", "wss://")
    |> String.replace("http://", "ws://")
    |> then(&"#{&1}/stream")
  end

  defp broadcast_chunk_to_ui(session_id, content) do
    Lightning.broadcast(
      "ai_session:#{session_id}",
      {:update, %{streaming_chunk: %{content: content}}}
    )
  end

  defp broadcast_status_to_ui(session_id, status) do
    Lightning.broadcast(
      "ai_session:#{session_id}",
      {:update, %{status_update: %{status: status}}}
    )
  end
end
