defmodule LightningWeb.WorkflowChannel do
  @moduledoc """
  Phoenix Channel for handling binary Yjs collaboration messages.

  Unlike LiveView events, Phoenix Channels properly support binary data
  transmission without JSON serialization.
  """
  use LightningWeb, :channel

  alias Lightning.Collaboration.Session
  alias Lightning.Collaboration.Utils

  require Logger

  @impl true
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

  @impl true
  def handle_in("yjs_sync", {:binary, chunk}, socket) do
    Session.start_sync(socket.assigns.session_pid, chunk)
    {:noreply, socket}
  end

  def handle_in("yjs", {:binary, chunk}, socket) do
    Logger.debug("""
    WorkflowChannel: handle_in, yjs
      from=#{inspect(self())}
      chunk=#{inspect(Utils.decipher_message(chunk))}
    """)

    Session.send_yjs_message(socket.assigns.session_pid, chunk)
    {:noreply, socket}
  end

  @impl true
  def handle_info({:yjs, chunk}, socket) do
    push(socket, "yjs", {:binary, chunk})
    {:noreply, socket}
  end

  @impl true
  def handle_info(
        {:DOWN, _ref, :process, _pid, _reason},
        socket
      ) do
    {:stop, {:error, "remote process crash"}, socket}
  end
end
