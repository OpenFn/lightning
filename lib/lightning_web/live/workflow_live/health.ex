defmodule LightningWeb.WorkflowLive.Health do
  @moduledoc """
  Workflow health page: a summary of a single workflow's work orders over the
  window the reader picks.
  """
  use LightningWeb, :live_view

  alias Lightning.Workflows

  on_mount {LightningWeb.Hooks, :project_scope}
  on_mount {LightningWeb.Hooks, :ensure_workflow_belongs_to_project}

  @impl true
  def mount(%{"id" => id}, _session, socket) do
    workflow = Workflows.get_workflow!(id)

    {:ok,
     assign(socket,
       active_menu_item: :overview,
       workflow: workflow,
       page_title: "Health Stats for #{workflow.name}"
     )}
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
              <LayoutComponents.breadcrumb_items items={[
                {"Workflows", ~p"/projects/#{@project}/w"},
                {@workflow.name, ~p"/projects/#{@project}/w/#{@workflow}"}
              ]} />
              <LayoutComponents.breadcrumb>
                <:label>Health</:label>
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
          data-react-file={~p"/assets/js/health/WorkflowHealth.js"}
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
