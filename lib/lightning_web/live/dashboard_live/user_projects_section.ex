defmodule LightningWeb.DashboardLive.UserProjectsSection do
  use LightningWeb, :live_component

  import LightningWeb.DashboardLive.Components

  alias Lightning.Accounts.User
  alias Lightning.Projects

  require Logger

  @impl true
  def update(assigns, socket) do
    projects = projects_for_user(assigns.current_user)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:projects, projects)
     |> assign(:name_sort_direction, :asc)
     |> assign(:last_activity_sort_direction, :asc)}
  end

  @impl true
  def handle_event("sort", %{"by" => field}, socket) do
    sort_key = String.to_atom("#{field}_sort_direction")
    order_column = String.to_atom(field)

    sort_direction =
      socket.assigns
      |> Map.get(sort_key, :asc)
      |> switch_sort_direction()

    projects =
      projects_for_user(socket.assigns.current_user,
        order_by: {sort_direction, order_column}
      )

    {:noreply,
     socket
     |> assign(:projects, projects)
     |> assign(sort_key, sort_direction)}
  end

  defp switch_sort_direction(:asc), do: :desc
  defp switch_sort_direction(:desc), do: :asc

  defp projects_for_user(%User{} = user, opts \\ []) do
    order_by = Keyword.get(opts, :order_by, {:asc, :name})

    Projects.get_projects_overview(user, order_by: order_by)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id}>
      <.user_projects_table
        projects={@projects}
        user={@current_user}
        target={@myself}
        name_direction={@name_sort_direction}
        last_activity_direction={@last_activity_sort_direction}
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
