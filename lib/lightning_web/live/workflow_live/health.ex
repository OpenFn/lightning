defmodule LightningWeb.WorkflowLive.Health do
  @moduledoc """
  Workflow health page: a 30-day summary of a single workflow's work orders.
  """
  use LightningWeb, :live_view

  alias Lightning.Workflows

  on_mount {LightningWeb.Hooks, :project_scope}
  on_mount {LightningWeb.Hooks, :ensure_workflow_belongs_to_project}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, active_menu_item: :overview)}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    workflow = Workflows.get_workflow!(id)

    {:noreply,
     socket
     |> assign(:workflow, workflow)
     |> assign(:page_title, workflow.name)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header current_user={@current_user}>
          <:breadcrumbs>
            <LayoutComponents.breadcrumbs>
              <LayoutComponents.breadcrumb_project_picker
                project={@project}
                label={@project_label}
              />
              <LayoutComponents.breadcrumb>
                <:label>{@workflow.name}</:label>
              </LayoutComponents.breadcrumb>
            </LayoutComponents.breadcrumbs>
          </:breadcrumbs>
        </LayoutComponents.header>
      </:header>

      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div
          id="workflow-health"
          phx-hook="ReactComponent"
          phx-update="ignore"
          data-react-name="WorkflowHealth"
          data-react-file={~p"/assets/js/workflow-health/WorkflowHealth.js"}
          data-workflow-id={@workflow.id}
          data-project-id={@project.id}
          data-workflow-name={@workflow.name}
        >
        </div>
      </div>
    </LayoutComponents.page_content>
    """
  end
end
