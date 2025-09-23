defmodule LightningWeb.ApolloChannel do
  @moduledoc """
  Websocket channel to handle streaming AI responses from Apollo server.
  """
  use LightningWeb, :channel

  require Logger

  @impl true
  def join("apollo:stream", _payload, socket) do
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
    # TODO implement the actual connection to Apollo
    # Now returning a mock stream reference
    stream_ref = :crypto.strong_rand_bytes(16) |> Base.encode64()
    {:ok, stream_ref}
  end
end
