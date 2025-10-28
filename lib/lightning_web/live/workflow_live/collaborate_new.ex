defmodule LightningWeb.WorkflowLive.CollaborateNew do
  @moduledoc """
  LiveView for collaborative creation of new workflows using shared Y.js documents.

  This LiveView allows users to create new workflows using the React collaborative editor.
  Unlike the regular Collaborate LiveView which requires an existing workflow ID, this
  creates an ephemeral workflow with a temporary UUID that gets persisted when the user
  saves for the first time.

  The workflow is created with a temporary ID and is not saved to the database until
  the user explicitly saves it via the React editor.
  """
  use LightningWeb, {:live_view, container: {:div, []}}

  alias Lightning.Workflows.Workflow

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    workflow_id = Ecto.UUID.generate()
    user_id = socket.assigns.current_user.id
    project = socket.assigns.project

    workflow = %Workflow{
      id: workflow_id,
      name: "Untitled Workflow",
      project_id: project.id
    }

    {:ok,
     socket
     |> assign(
       active_menu_item: :overview,
       page_title: "New Workflow",
       workflow: workflow,
       workflow_id: workflow_id,
       user_id: user_id,
       project: project
     )}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div
      id="collaborative-editor-react"
      class="h-full"
      phx-hook="ReactComponent"
      data-react-name="CollaborativeEditor"
      data-react-file={~p"/assets/js/collaborative-editor/CollaborativeEditor.js"}
      data-workflow-id={@workflow_id}
      data-workflow-name={@workflow.name}
      data-project-id={@workflow.project_id}
      data-project-name={@project.name}
      data-project-color={@project.color}
      data-root-project-id={
        if @project.parent, do: Lightning.Projects.root_of(@project).id, else: nil
      }
      data-root-project-name={
        if @project.parent, do: Lightning.Projects.root_of(@project).name, else: nil
      }
      data-project-env={@project.env}
      data-is-new-workflow="true"
    />
    """
  end
end
