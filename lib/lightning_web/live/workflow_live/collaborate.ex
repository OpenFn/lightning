defmodule LightningWeb.WorkflowLive.Collaborate do
  @moduledoc """
  LiveView for collaborative workflow editing using shared Y.js documents.
  """
  use LightningWeb, {:live_view, container: {:div, []}}

  alias Lightning.Workflows

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(%{"id" => workflow_id}, _session, socket) do
    workflow = Workflows.get_workflow!(workflow_id)
    user_id = socket.assigns.current_user.id

    {:ok,
     socket
     |> assign(
       active_menu_item: :overview,
       page_title: "Collaborate on #{workflow.name}",
       workflow: workflow,
       workflow_id: workflow_id,
       user_id: user_id
     )}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="flex flex-col h-full">
      <div class="flex-1 p-4">
        <h2 class="text-2xl font-bold mb-4">
          Collaborative Workflow Editor - {@workflow.name}
        </h2>

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
      </div>
    </div>
    """
  end
end
