defmodule LightningWeb.WorkflowChannel do
  @moduledoc """
  Phoenix Channel for handling binary Yjs collaboration messages.

  Unlike LiveView events, Phoenix Channels properly support binary data
  transmission without JSON serialization.
  """
  use Phoenix.Channel

  def join("workflow:collaborate:" <> workflow_id = topic, _params, socket) do
    # Check if user is authenticated
    case socket.assigns[:current_user] do
      nil ->
        {:error, %{reason: "unauthorized"}}

      user ->
        # Get workflow and verify user has access to its project
        case Lightning.Workflows.get_workflow(workflow_id, include: [:project]) do
          nil ->
            {:error, %{reason: "workflow not found"}}

          workflow ->
            case Lightning.Policies.Workflows.authorize(
                   :access_read,
                   user,
                   workflow.project
                 ) do
              :ok ->
                # Subscribe to PubSub for this workflow
                Phoenix.PubSub.subscribe(Lightning.PubSub, topic)

                {:ok,
                 assign(socket,
                   workflow_id: workflow_id,
                   collaboration_topic: topic,
                   workflow: workflow
                 )}

              {:error, :unauthorized} ->
                {:error, %{reason: "unauthorized"}}
            end
        end
    end
  end

  # Handle Yjs protocol messages (used for sync and awareness)
  def handle_in("yjs", {:binary, payload}, socket) do
    IO.inspect(byte_size(payload), label: "Received binary yjs message")

    # Broadcast to other channel processes
    Phoenix.PubSub.broadcast_from(
      Lightning.PubSub,
      self(),
      socket.assigns.collaboration_topic,
      {:yjs, payload}
    )

    {:noreply, socket}
  end

  # Handle JSON-encoded Yjs messages (fallback for Phoenix.js JSON encoding)
  def handle_in("yjs", payload, socket) when is_map(payload) do
    binary_payload = convert_json_to_binary(payload)

    IO.inspect(byte_size(binary_payload),
      label: "Received JSON yjs message, converted to binary"
    )

    # Broadcast to other channel processes
    Phoenix.PubSub.broadcast_from(
      Lightning.PubSub,
      self(),
      socket.assigns.collaboration_topic,
      {:yjs, binary_payload}
    )

    {:noreply, socket}
  end

  # Handle Yjs sync messages (initial sync)
  def handle_in("yjs_sync", {:binary, payload}, socket) do
    IO.inspect(byte_size(payload), label: "Received binary yjs_sync message")

    Phoenix.PubSub.broadcast_from(
      Lightning.PubSub,
      self(),
      socket.assigns.collaboration_topic,
      {:yjs_sync, payload}
    )

    {:noreply, socket}
  end

  # Handle JSON-encoded sync messages (fallback)
  def handle_in("yjs_sync", payload, socket) when is_map(payload) do
    binary_payload = convert_json_to_binary(payload)

    IO.inspect(byte_size(binary_payload),
      label: "Received JSON yjs_sync message, converted to binary"
    )

    Phoenix.PubSub.broadcast_from(
      Lightning.PubSub,
      self(),
      socket.assigns.collaboration_topic,
      {:yjs_sync, binary_payload}
    )

    {:noreply, socket}
  end

  # Handle PubSub broadcasts from other channel processes
  def handle_info({:yjs, payload}, socket) do
    push(socket, "yjs", {:binary, payload})
    {:noreply, socket}
  end

  def handle_info({:yjs_sync, payload}, socket) do
    push(socket, "yjs_sync", {:binary, payload})
    {:noreply, socket}
  end

  # Helper function to convert JSON object with numeric keys back to binary
  defp convert_json_to_binary(payload) when is_map(payload) do
    # Phoenix.js converts Uint8Array to object with numeric string keys
    # e.g., %{"0" => 1, "1" => 137, "2" => 170, ...}

    # Get all numeric keys and sort them
    keys =
      payload
      |> Map.keys()
      |> Enum.map(&String.to_integer/1)
      |> Enum.sort()

    # Extract values in order and convert to binary
    keys
    |> Enum.map(&Map.get(payload, Integer.to_string(&1)))
    |> :binary.list_to_bin()
  end
end
