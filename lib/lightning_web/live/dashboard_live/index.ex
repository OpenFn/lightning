defmodule LightningWeb.DashboardLive.Index do
  use LightningWeb, :live_view

  import LightningWeb.DashboardLive.Components

  require Logger

  on_mount {LightningWeb.Hooks, :project_scope}
  on_mount {LightningWeb.Hooks, :assign_projects}
  on_mount {LightningWeb.Hooks, :check_limits}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, page_title: "Projects", active_menu_item: :projects)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:banner>
        <Common.dynamic_component
          :if={assigns[:banner]}
          function={@banner.function}
          args={@banner.attrs}
        />
      </:banner>
      <:header>
        <LayoutComponents.header current_user={@current_user}>
          <:title>{@page_title}</:title>
        </LayoutComponents.header>
      </:header>

      <LayoutComponents.centered>
        <div class="w-full -mt-6">
          <div>
            <.welcome_banner
              id="projects-dashboard-welcome-section"
              user={@current_user}
            />
          </div>

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
