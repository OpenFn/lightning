defmodule LightningWeb.DashboardLive.Index do
  use LightningWeb, :live_view

  require Logger

  on_mount {LightningWeb.Hooks, :project_scope}
  on_mount {LightningWeb.Hooks, :assign_projects}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Projects", active_menu_item: :projects)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header current_user={@current_user}>
          <:title>{@page_title}</:title>
        </LayoutComponents.header>
      </:header>

      <LayoutComponents.centered>
        <div class="w-full">
          <.live_component
            id="projects-dashboard-welcome-section"
            module={LightningWeb.DashboardLive.WelcomeSection}
            current_user={@current_user}
          />

          <.live_component
            id="user-projects-section"
            module={LightningWeb.DashboardLive.UserProjectsSection}
            current_user={@current_user}
          />

          <.live_component
            id="create-project-modal"
            module={LightningWeb.DashboardLive.ProjectCreationModal}
            current_user={@current_user}
            return_to={~p"/projects"}
          />
        </div>
      </LayoutComponents.centered>
    </LayoutComponents.page_content>
    """
  end
end
