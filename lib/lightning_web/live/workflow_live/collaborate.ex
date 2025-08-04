defmodule LightningWeb.WorkflowLive.Collaborate do
  @moduledoc """
  LiveView for collaborative workflow editing using shared Y.js documents.
  """
  use LightningWeb, {:live_view, container: {:div, []}}

  alias Lightning.Workflows
  alias Lightning.WorkflowCollaboration

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(%{"id" => workflow_id}, _session, socket) do
    workflow = Workflows.get_workflow!(workflow_id)
    user_id = socket.assigns.current_user.id

    # Join the collaborative workflow session
    case WorkflowCollaboration.join_workflow(workflow_id, user_id) do
      {:ok, collaborator_pid, _initial_doc_state} ->
        # Monitor the collaborator process
        Process.monitor(collaborator_pid)

        # Observe Y.js updates from the shared document
        WorkflowCollaboration.observe_document(collaborator_pid)

        # Get the current shared document state
        shared_doc = WorkflowCollaboration.get_document(collaborator_pid)

        # Access shared structures
        counter_map = Yex.Doc.get_map(shared_doc, "counter_data")

        # Get current counter value and timestamp
        initial_counter =
          case Yex.Map.fetch(counter_map, "value") do
            {:ok, value} -> value
            :error -> 0
          end

        initial_timestamp =
          case Yex.Map.fetch(counter_map, "last_updated") do
            {:ok, timestamp} -> timestamp
            :error -> DateTime.utc_now() |> DateTime.to_iso8601()
          end

        {:ok,
         socket
         |> assign(
           active_menu_item: :overview,
           page_title: "Collaborate on #{workflow.name}",
           workflow: workflow,
           workflow_id: workflow_id,
           user_id: user_id,
           collaborator_pid: collaborator_pid,
           counter: initial_counter,
           last_updated: initial_timestamp
         )}

      {:error, reason} ->
        {:ok,
         socket
         |> put_flash(
           :error,
           "Failed to join collaborative session: #{inspect(reason)}"
         )
         |> assign(
           active_menu_item: :overview,
           page_title: "Collaborate on #{workflow.name}",
           workflow: workflow,
           error: true
         )}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  # Handle Y.js messages from the shared document
  @impl true
  def handle_info({:yjs, _message, _server_pid}, socket) do
    IO.inspect({self(), socket.assigns[:collaborator_pid]},
      label: "handle_info :yjs"
    )

    # Refresh counter and timestamp from shared document when we receive updates
    if socket.assigns[:collaborator_pid] do
      shared_doc =
        WorkflowCollaboration.get_document(socket.assigns.collaborator_pid)

      counter_map = Yex.Doc.get_map(shared_doc, "counter_data")

      updated_counter =
        case Yex.Map.fetch(counter_map, "value") do
          {:ok, value} -> value
          :error -> 0
        end

      updated_timestamp =
        case Yex.Map.fetch(counter_map, "last_updated") do
          {:ok, timestamp} -> timestamp
          :error -> DateTime.utc_now() |> DateTime.to_iso8601()
        end

      {:noreply,
       assign(socket, counter: updated_counter, last_updated: updated_timestamp)}
    else
      {:noreply, socket}
    end
  end

  # Handle collaborator process going down
  @impl true
  def handle_info({:DOWN, _ref, :process, pid, reason}, socket) do
    if socket.assigns[:collaborator_pid] == pid do
      {:noreply,
       socket
       |> put_flash(
         :error,
         "Collaborative session disconnected: #{inspect(reason)}"
       )
       |> assign(error: true)}
    else
      {:noreply, socket}
    end
  end

  # Handle increment button
  @impl true
  def handle_event("increment", _params, socket) do
    if socket.assigns[:collaborator_pid] && !socket.assigns[:error] do
      # Update counter via shared document
      WorkflowCollaboration.update_document(
        socket.assigns.collaborator_pid,
        fn doc ->
          counter_map = Yex.Doc.get_map(doc, "counter_data")

          current_counter =
            case Yex.Map.fetch(counter_map, "value") do
              {:ok, value} -> value
              :error -> 0
            end

          new_counter = current_counter + 1
          timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

          Yex.Map.set(counter_map, "value", new_counter)
          Yex.Map.set(counter_map, "last_updated", timestamp)
        end
      )
    end

    {:noreply, socket}
  end

  # Handle decrement button
  @impl true
  def handle_event("decrement", _params, socket) do
    if socket.assigns[:collaborator_pid] && !socket.assigns[:error] do
      # Update counter via shared document
      WorkflowCollaboration.update_document(
        socket.assigns.collaborator_pid,
        fn doc ->
          counter_map = Yex.Doc.get_map(doc, "counter_data")

          current_counter =
            case Yex.Map.fetch(counter_map, "value") do
              {:ok, value} -> value
              :error -> 0
            end

          new_counter = current_counter - 1
          timestamp = DateTime.utc_now() |> DateTime.to_iso8601()

          Yex.Map.set(counter_map, "value", new_counter)
          Yex.Map.set(counter_map, "last_updated", timestamp)
        end
      )
    end

    {:noreply, socket}
  end

  # Handle Yjs update events from React component
  @impl true
  def handle_event(
        "yjs_update",
        %{"type" => type, "payload" => payload} = params,
        socket
      ) do
    IO.inspect({type, payload, params}, label: "yjs_update received")

    # For now, just log the message and acknowledge receipt
    # In Phase 4, we would integrate this with WorkflowCollaboration

    {:noreply, socket}
  end

  # Handle Yjs awareness events from React component
  @impl true
  def handle_event(
        "yjs_awareness",
        %{"type" => type, "payload" => payload} = params,
        socket
      ) do
    IO.inspect({type, payload, params}, label: "yjs_awareness received")

    # For now, just log the message and acknowledge receipt
    # In Phase 4, we would broadcast awareness updates to other clients

    {:noreply, socket}
  end

  # Handle sync requests from React component
  @impl true
  def handle_event(
        "sync_request",
        %{"type" => type, "payload" => payload} = params,
        socket
      ) do
    IO.inspect({type, payload, params}, label: "sync_request received")

    # For now, just log the message and acknowledge receipt
    # In Phase 4, we would handle document synchronization

    {:noreply, socket}
  end

  # Handle Yjs responses from React component
  @impl true
  def handle_event(
        "yjs_response",
        %{"type" => type, "payload" => payload} = params,
        socket
      ) do
    IO.inspect({type, payload, params}, label: "yjs_response received")

    # For now, just log the message and acknowledge receipt

    {:noreply, socket}
  end

  # Handle Yjs awareness queries from React component
  @impl true
  def handle_event(
        "yjs_query_awareness",
        %{"type" => type, "payload" => payload} = params,
        socket
      ) do
    IO.inspect({type, payload, params}, label: "yjs_query_awareness received")

    # For now, just log the message and acknowledge receipt
    # In Phase 4, we would return current awareness state

    {:noreply, socket}
  end

  # Clean up when LiveView terminates
  @impl true
  def terminate(reason, socket) do
    IO.inspect(reason, label: "terminate")

    if socket.assigns[:collaborator_pid] do
      WorkflowCollaboration.leave_workflow(
        socket.assigns.collaborator_pid,
        self()
      )
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <div class="flex-1 p-4">
        <h2 class="text-2xl font-bold mb-4">
          Collaborative Workflow Editor - {@workflow.name}
        </h2>

        <%= if assigns[:error] do %>
          <div class="mb-6 p-4 bg-red-50 border border-red-200 rounded-lg">
            <h3 class="text-lg font-semibold text-red-800 mb-2">
              ⚠️ Collaboration Unavailable
            </h3>
            <p class="text-red-700">
              Unable to join collaborative session. Check the logs for details.
            </p>
          </div>
        <% else %>
          <!-- Collaborative Editor React Component -->
          <div
            id="collaborative-editor-react"
            phx-hook="ReactComponent"
            data-react-name="CollaborativeEditor"
            data-react-file={~p"/assets/js/react/components/CollaborativeEditor.js"}
            data-workflow-id={@workflow_id}
            data-workflow-name={@workflow.name}
            data-user-id={@user_id}
            data-user-name={@current_user.first_name <> " " <> @current_user.last_name}
          />
          
    <!-- Original Counter Demo (keeping for comparison) -->
          <div class="mt-8 pt-8 border-t border-gray-200">
            <h3 class="text-lg font-semibold mb-4 text-gray-700">
              Original Counter Demo (Y.js Backend Integration)
            </h3>
            <div class="max-w-md mx-auto">
              <div class="text-center mb-6">
                <div class="text-4xl font-bold text-blue-600 mb-2">
                  {assigns[:counter] || 0}
                </div>
                <p class="text-sm text-gray-600">
                  Shared counter (synced across all users)
                </p>
              </div>

              <div class="flex gap-4 justify-center mb-6">
                <button
                  phx-click="decrement"
                  class="px-4 py-2 bg-red-500 hover:bg-red-600 text-white font-semibold rounded-lg shadow-md transition-colors"
                >
                  - Decrement
                </button>
                <button
                  phx-click="increment"
                  class="px-4 py-2 bg-green-500 hover:bg-green-600 text-white font-semibold rounded-lg shadow-md transition-colors"
                >
                  + Increment
                </button>
              </div>

              <div class="text-center text-sm text-gray-500">
                <p><strong>Last updated:</strong></p>
                <p class="font-mono text-xs">{assigns[:last_updated] || "Never"}</p>
                <p class="mt-2 text-xs">
                  Open multiple browser tabs to see real-time collaboration
                </p>
              </div>
            </div>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
