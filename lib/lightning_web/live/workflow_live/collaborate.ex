defmodule LightningWeb.WorkflowLive.Collaborate do
  @moduledoc """
  LiveView for collaborative workflow editing using Yjs.
  """
  use LightningWeb, {:live_view, container: {:div, []}}

  alias Lightning.Workflows
  import LightningWeb.Components.CollaborativeEditor

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(%{"id" => workflow_id}, _session, socket) do
    workflow = Workflows.get_workflow!(workflow_id)

    {:ok,
     socket
     |> assign(
       active_menu_item: :overview,
       page_title: "Collaborate on #{workflow.name}",
       workflow: workflow
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
        <.CollaborativeEditor
          workflow_id={@workflow.id}
          workflow_name={@workflow.name}
        />
      </div>
    </div>
    """
  end
end
