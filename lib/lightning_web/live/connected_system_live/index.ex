defmodule LightningWeb.ConnectedSystemLive.Index do
  use LightningWeb, :live_view

  import LightningWeb.ConnectedSystemLive.Components

  alias Lightning.ConnectedSystems
  alias Lightning.ConnectedSystems.ConnectedSystem
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Users

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    can_access_admin_space =
      Users
      |> Permissions.can?(:access_admin_space, socket.assigns.current_user, {})

    if can_access_admin_space do
      {:ok,
       socket
       |> assign(
         page_title: "Systems",
         active_menu_item: :connected_systems,
         connected_systems: ConnectedSystems.list_connected_systems(),
         sort_by: "name",
         sort_direction: :asc
       ), layout: {LightningWeb.Layouts, :settings}}
    else
      {:ok,
       socket
       |> put_flash(:nav, :no_access)
       |> push_navigate(to: "/projects")}
    end
  end

  @impl true
  def handle_event("sort", %{"by" => field}, socket)
      when field in ~w(name type) do
    new_direction =
      if socket.assigns.sort_by == field do
        switch_sort_direction(socket.assigns.sort_direction)
      else
        :asc
      end

    connected_systems =
      ConnectedSystems.list_connected_systems(
        order_by: [{new_direction, String.to_existing_atom(field)}]
      )

    {:noreply,
     socket
     |> assign(:connected_systems, connected_systems)
     |> assign(:sort_by, field)
     |> assign(:sort_direction, new_direction)}
  end

  def handle_event(
        "delete_connected_system",
        %{"connected_system" => id},
        socket
      ) do
    case ConnectedSystems.delete_connected_system(id) do
      {:ok, _connected_system} ->
        {:noreply,
         socket
         |> put_flash(:info, "System deleted")
         |> push_navigate(to: ~p"/settings/connected_systems")}

      {:error, reason} ->
        Logger.error("Error during connected system deletion: #{inspect(reason)}")

        {:noreply,
         socket
         |> put_flash(:error, "Couldn't delete system!")
         |> push_navigate(to: ~p"/settings/connected_systems")}
    end
  end

  defp switch_sort_direction(:asc), do: :desc
  defp switch_sort_direction(:desc), do: :asc

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
          <.connected_systems_table
            connected_systems={@connected_systems}
            sort_by={@sort_by}
            sort_direction={@sort_direction}
          >
            <:empty_state>
              <.empty_state
                icon="hero-plus-circle"
                message="No systems found."
                button_text="Add a system."
                button_id="open-create-connected-system-modal-big-button"
                button_click={show_modal("create-connected-system-modal")}
                button_disabled={false}
              />
            </:empty_state>
            <:create_connected_system_button>
              <.button
                role="button"
                id="open-create-connected-system-modal-button"
                phx-click={show_modal("create-connected-system-modal")}
                class="col-span-1 w-full"
                theme="primary"
              >
                Add system
              </.button>
            </:create_connected_system_button>
          </.connected_systems_table>
          <.live_component
            id="create-connected-system-modal"
            module={LightningWeb.ConnectedSystemLive.ConnectedSystemFormModal}
            connected_system={%ConnectedSystem{}}
            return_to={~p"/settings/connected_systems"}
          />
        </div>
      </LayoutComponents.centered>
    </LayoutComponents.page_content>
    """
  end
end
