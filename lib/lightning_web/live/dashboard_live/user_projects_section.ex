defmodule LightningWeb.DashboardLive.UserProjectsSection do
  use LightningWeb, :live_component

  import LightningWeb.DashboardLive.Components

  alias Lightning.Projects

  require Logger

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(sort_key: "name", sort_direction: "asc")
     |> assign_projects()}
  end

  @impl true
  def handle_event("sort", %{"by" => field}, socket) do
    sort_assigns =
      case socket.assigns do
        %{sort_key: ^field, sort_direction: direction} ->
          %{sort_key: field, sort_direction: switch_sort_direction(direction)}

        _new_sort_key ->
          %{sort_key: field, sort_direction: "asc"}
      end

    {:noreply,
     socket
     |> assign(sort_assigns)
     |> assign_projects()}
  end

  defp switch_sort_direction("asc"), do: "desc"
  defp switch_sort_direction("desc"), do: "asc"

  defp assign_projects(%{assigns: assigns} = socket) do
    sort_param = {
      String.to_existing_atom(assigns.sort_key),
      String.to_existing_atom(assigns.sort_direction)
    }

    projects =
      Projects.get_projects_overview(assigns.current_user, order_by: sort_param)

    assign(socket, :projects, projects)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.user_projects_table
        projects={@projects}
        user={@current_user}
        target={@myself}
        sort_key={@sort_key}
        sort_direction={@sort_direction}
      >
        <:empty_state>
          <button
            type="button"
            id="open-create-project-modal-big-button"
            phx-click={show_modal("create-project-modal")}
            class="relative block w-full rounded-lg border-2 border-dashed p-4 text-center hover:border-gray-400"
          >
            <Heroicons.plus_circle class="mx-auto w-12 h-12 text-secondary-400" />
            <span class="mt-2 block text-xs font-semibold text-secondary-600">
              No projects found. Create a new one.
            </span>
          </button>
        </:empty_state>
        <:create_project_button>
          <.button
            id="open-create-project-modal-button"
            phx-click={show_modal("create-project-modal")}
            class="w-full rounded-md"
          >
            Create project
          </.button>
        </:create_project_button>
      </.user_projects_table>
    </div>
    """
  end
end
