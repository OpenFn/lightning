defmodule LightningWeb.ProjectLive.Health do
  @moduledoc """
  Project health page: a 30-day summary of the work orders across every
  workflow in the project.

  The shell only — the project name and the work order count. Charts follow;
  the aggregation and its endpoint already exist in `Lightning.Workflows.Stats`
  and `LightningWeb.API.ProjectHealthController`.
  """
  use LightningWeb, :live_view

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active_menu_item, :overview)
     |> assign(:page_title, socket.assigns.project.name)}
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
                <:label>Health</:label>
              </LayoutComponents.breadcrumb>
            </LayoutComponents.breadcrumbs>
          </:breadcrumbs>
        </LayoutComponents.header>
      </:header>

      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <div
          id="project-health"
          phx-hook="ReactComponent"
          phx-update="ignore"
          data-react-name="ProjectHealth"
          data-react-file={~p"/assets/js/health/ProjectHealth.js"}
          data-project-id={@project.id}
          data-project-name={@project.name}
        >
        </div>
      </div>
    </LayoutComponents.page_content>
    """
  end
end
