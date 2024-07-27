defmodule LightningWeb.DashboardLive.Index do
  use LightningWeb, :live_view

  alias Lightning.Accounts.User
  alias Lightning.Projects

  import LightningWeb.DashboardLive.Components

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    projects = projects_for_user(socket.assigns.current_user)

    {:ok, assign(socket, projects: projects, active_menu_item: :projects)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply,
     assign(socket, page_title: "Projects", active_menu_item: :projects)}
  end

  defp projects_for_user(%User{} = user) do
    Projects.get_projects_for_user(user, include: [:project_users, :workflows])
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header current_user={@current_user}>
          <:title><%= @page_title %></:title>
        </LayoutComponents.header>
      </:header>
      <LayoutComponents.centered>
        <div class="w-full">
          <.user_projects_table projects={@projects} user={@current_user}>
            <:empty_state>
              <button
                type="button"
                id="open-create-project-modal-big-buttton"
                phx-click={show_modal("create-project-modal")}
                class="relative block w-full rounded-lg border-2 border-dashed border-gray-300 p-4 text-center hover:border-gray-400 focus:outline-none"
              >
                <Heroicons.plus_circle class="mx-auto w-12 h-12 text-secondary-400" />
                <span class="mt-2 block text-xs font-semibold text-secondary-600">
                  No projects found. Create a new one.
                </span>
              </button>
            </:empty_state>
            <:create_project_button>
              <.button
                role="button"
                id="open-create-project-modal-button"
                phx-click={show_modal("create-project-modal")}
                class="col-span-1 w-full rounded-md"
              >
                Create new project
              </.button>
            </:create_project_button>
          </.user_projects_table>
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
