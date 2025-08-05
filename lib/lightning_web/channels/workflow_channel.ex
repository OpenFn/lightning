defmodule LightningWeb.WorkflowChannel do
  @moduledoc """
  Phoenix Channel for handling binary Yjs collaboration messages.

  Unlike LiveView events, Phoenix Channels properly support binary data
  transmission without JSON serialization.
  """
  use Phoenix.Channel

  alias Lightning.Collaboration.Session

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
            case Lightning.Policies.Permissions.can(
                   :workflows,
                   :access_read,
                   user,
                   workflow.project
                 ) do
              :ok ->
                {:ok, session_pid} =
                  Session.start(workflow_id)

                {:ok,
                 assign(socket,
                   workflow_id: workflow_id,
                   collaboration_topic: topic,
                   workflow: workflow,
                   session_pid: session_pid
                 )}

              {:error, :unauthorized} ->
                {:error, %{reason: "unauthorized"}}
            end
        end
    end
  end

  # Handle Yjs protocol messages (used for sync and awareness)
  def handle_in("yjs", {:binary, payload}, socket) do
    Session.send_yjs_message(socket.assigns.session_pid, payload)

    {:noreply, socket}
  end

  # Handle Yjs sync messages (initial sync)
  def handle_in("yjs_sync", {:binary, chunk}, socket) do
    Session.start_sync(socket.assigns.session_pid, chunk)

    {:noreply, socket}
  end

  # Handle PubSub broadcasts from other channel processes
  def handle_info({:yjs, payload}, socket) do
    push(socket, "yjs", {:binary, payload})
    {:noreply, socket}
  end
end
