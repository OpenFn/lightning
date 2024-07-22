defmodule LightningWeb.DashboardLive.Index do
  use LightningWeb, :live_view

  alias Lightning.Projects

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    projects =
      socket.assigns.current_user
      |> Projects.get_projects_for_user(
        include: [
          :project_users,
          :workflows
        ]
      )

    {:ok,
     socket |> assign(:projects, projects) |> assign(active_menu_item: :projects)}
  end

  @impl true
  def handle_params(_params, url, socket) do
    return_to = url |> URI.parse() |> Map.get(:path)

    {:noreply,
     socket
     |> assign(
       page_title: "Projects",
       active_menu_item: :projects,
       return_to: return_to
     )}
  end

  defp project_role(user, project) do
    project.project_users
    |> Enum.find(fn project_user -> project_user.user_id == user.id end)
    |> Map.get(:role)
    |> Atom.to_string()
    |> String.capitalize()
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
          <%= if Enum.empty?(@projects) do %>
            <button
              type="button"
              id="open-create-project-modal-big-buttton"
              phx-click={show_modal("new-project-modal")}
              class="relative block w-full rounded-lg border-2 border-dashed border-gray-300 p-4 text-center hover:border-gray-400 focus:outline-none"
            >
              <Heroicons.plus_circle class="mx-auto w-12 h-12 text-secondary-400" />
              <span class="mt-2 block text-xs font-semibold text-secondary-600">
                No projects found. Create a new one.
              </span>
            </button>
          <% else %>
            <div class="mt-5 flex justify-between mb-3">
              <h3 class="text-3xl font-bold">
                Projects
                <span class="text-base font-normal">
                  (<%= length(@projects) %>)
                </span>
              </h3>
              <div>
                <.button
                  role="button"
                  id="open-create-project-modal-button"
                  phx-click={show_modal("new-project-modal")}
                  class="col-span-1 w-full rounded-md"
                >
                  Create new project
                </.button>
              </div>
            </div>
            <.table id="projects-table">
              <.tr>
                <.th>Name</.th>
                <.th>Role</.th>
                <.th>Workflows</.th>
                <.th>Collaborators</.th>
                <.th>Last Activity</.th>
              </.tr>

              <.tr
                :for={project <- @projects}
                id={"projects-table-row-#{project.id}"}
                class="hover:bg-gray-100 transition-colors duration-200"
              >
                <.td class="break-words max-w-[15rem] flex items-center">
                  <.link class="text-gray-800" href={~p"/projects/#{project.id}/w"}>
                    <%= project.name %>
                  </.link>
                </.td>
                <.td class="break-words max-w-[25rem]">
                  <%= project_role(@current_user, project) %>
                </.td>
                <.td class="break-words max-w-[10rem]">
                  <%= length(project.workflows) %>
                </.td>
                <.td class="break-words max-w-[5rem]">
                  <.link
                    class="text-primary-700"
                    href={~p"/projects/#{project.id}/settings#collaboration"}
                  >
                    <%= length(project.project_users) %>
                  </.link>
                </.td>
                <.td>
                  <%= Lightning.Helpers.format_date(
                    project.updated_at,
                    "%d/%b/%Y %H:%M:%S"
                  ) %>
                </.td>
              </.tr>
            </.table>
          <% end %>
          <.live_component
            id="new-project-modal"
            module={LightningWeb.DashboardLive.NewProjectModal}
            current_user={@current_user}
            return_to={@return_to}
          />
        </div>
      </LayoutComponents.centered>
    </LayoutComponents.page_content>
    """
  end
end
