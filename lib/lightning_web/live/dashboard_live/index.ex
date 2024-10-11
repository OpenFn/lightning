defmodule LightningWeb.DashboardLive.Index do
  use LightningWeb, :live_view
  import LightningWeb.DashboardLive.Components

  alias Lightning.Accounts.User
  alias Lightning.Projects

  on_mount {LightningWeb.Hooks, :project_scope}

  @resources [
    %{
      id: 1,
      title: "Getting Started with OpenFn",
      link:
        "https://demo.arcade.software/WhOK61AiXdG73Dd5lfSa?embed&embed_mobile=inline&embed_desktop=inline&show_copy_link=true"
    },
    %{
      id: 2,
      title: "Creating your first workflow",
      link:
        "https://demo.arcade.software/WhOK61AiXdG73Dd5lfSa?embed&embed_mobile=inline&embed_desktop=inline&show_copy_link=true"
    },
    %{
      id: 3,
      title: "How to use the IDE",
      link:
        "https://demo.arcade.software/WhOK61AiXdG73Dd5lfSa?embed&embed_mobile=inline&embed_desktop=inline&show_copy_link=true"
    },
    %{
      id: 4,
      title: "Managing project history",
      link:
        "https://demo.arcade.software/WhOK61AiXdG73Dd5lfSa?embed&embed_mobile=inline&embed_desktop=inline&show_copy_link=true"
    }
  ]

  @impl true
  def mount(_params, _session, socket) do
    projects = projects_for_user(socket.assigns.current_user)

    {:ok,
     assign_new(socket, :projects, fn -> projects end)
     |> assign(:resources, @resources)
     |> assign(:active_menu_item, :projects)
     |> assign(:arcade_banner_collapsed, true)
     |> assign(:open_modal, nil)
     |> assign(:name_sort_direction, :asc)
     |> assign(:activity_sort_direction, :asc)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, assign(socket, page_title: "Projects")}
  end

  @impl true
  def handle_event("sort", %{"by" => field}, socket) do
    sort_key = String.to_atom("#{field}_sort_direction")
    sort_direction = Map.get(socket.assigns, sort_key, :asc)
    new_sort_direction = switch_sort_direction(sort_direction)

    order_column = map_sort_field_to_column(field)

    projects =
      projects_for_user(socket.assigns.current_user,
        order_by: [{new_sort_direction, order_column}]
      )

    socket =
      socket
      |> assign(:projects, projects)
      |> assign(sort_key, new_sort_direction)

    {:noreply, socket}
  end

  def handle_event(
        "open-arcade-modal",
        %{"id" => id, "title" => title, "link" => link},
        socket
      ) do
    {:noreply, assign(socket, open_modal: %{id: id, title: title, link: link})}
  end

  def handle_event("close_arcade_modal", _, socket) do
    {:noreply, assign(socket, open_modal: nil)}
  end

  def handle_event("toggle_arcade_banner", _params, socket) do
    {:noreply,
     assign(socket,
       arcade_banner_collapsed: !socket.assigns.arcade_banner_collapsed
     )}
  end

  defp switch_sort_direction(:asc), do: :desc
  defp switch_sort_direction(:desc), do: :asc

  defp map_sort_field_to_column("name"), do: :name
  defp map_sort_field_to_column("activity"), do: :updated_at
  defp map_sort_field_to_column(_), do: :name

  defp projects_for_user(%User{} = user, opts \\ []) do
    include = Keyword.get(opts, :include, [:project_users, :workflows])
    order_by = Keyword.get(opts, :order_by, asc: :name)

    Projects.get_projects_for_user(user, include: include, order_by: order_by)
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
          <.arcade_banner
            resources={@resources}
            collapsed={@arcade_banner_collapsed}
            open_modal={@open_modal}
            current_user={@current_user}
          />

          <.user_projects_table
            projects={@projects}
            user={@current_user}
            name_direction={@name_sort_direction}
            activity_direction={@activity_sort_direction}
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

  def arcade_banner(assigns) do
    ~H"""
    <div class="rounded-lg pb-6">
      <div class="flex justify-between items-center pt-6">
        <h1 class="text-xl font-bold">
          Good day, <%= @current_user.first_name %>!
        </h1>
        <button
          phx-click="toggle_arcade_banner"
          class="text-gray-500 focus:outline-none"
        >
          <span class="text-lg">
            <.icon name={"hero-chevron-#{if @collapsed, do: "down", else: "up"}"} />
          </span>
        </button>
      </div>

      <div
        id="arcade-banner-content"
        class={"transition-all duration-500 ease-in-out overflow-hidden #{banner_content_classes(@collapsed)}"}
      >
        <p class="mb-6 mt-4">
          Here are some resources to help you get started with OpenFn
        </p>
        <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-4 gap-6">
          <%= for %{id: id, title: title, link: link} <- @resources do %>
            <.resource_card id={id} title={title} link={link} />
          <% end %>
        </div>
      </div>

      <hr class="border-t border-gray-300 mt-4" />
      <.arcade_modal
        :if={@open_modal}
        id={"arcade-modal-#{@open_modal.id}"}
        title={@open_modal.title}
        link={@open_modal.link}
      />
    </div>
    """
  end

  defp banner_content_classes(true), do: "max-h-0"
  # Adjust as needed
  defp banner_content_classes(false), do: "max-h-[500px]"

  def resource_card(assigns) do
    ~H"""
    <button
      type="button"
      phx-click="open-arcade-modal"
      phx-value-id={@id}
      phx-value-title={@title}
      phx-value-link={@link}
      class="relative flex items-end h-[150px] bg-gradient-to-r from-blue-400 to-purple-500 text-white rounded-lg shadow-md hover:shadow-lg transition-shadow duration-300 p-4"
    >
      <h2 class="text-lg font-semibold absolute bottom-4 left-4"><%= @title %></h2>
    </button>
    """
  end

  def arcade_modal(assigns) do
    ~H"""
    <div class="text-xs">
      <.modal id={@id} with_frame={false} show={true} width="w-5/6">
        <div style="position: relative; padding-bottom: calc(56.67989417989418% + 41px); height: 0; width: 100%;">
          <iframe
            src={@link}
            title={@title}
            frameborder="0"
            loading="lazy"
            webkitallowfullscreen
            mozallowfullscreen
            allowfullscreen
            allow="clipboard-write"
            style="position: absolute; top: 0; left: 0; width: 100%; height: 100%; color-scheme: light;"
          >
          </iframe>
        </div>
      </.modal>
    </div>
    """
  end
end
