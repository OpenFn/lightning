defmodule LightningWeb.ConnectedSystemsLive.Index do
  @moduledoc """
  Deployment-level admin view for the Connected Systems registry: the
  organization-wide catalog of external systems credentials can reference.
  """
  use LightningWeb, :live_view

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
         active_menu_item: :connected_systems,
         connected_systems: ConnectedSystems.list_connected_systems()
       ), layout: {LightningWeb.Layouts, :settings}}
    else
      {:ok,
       socket
       |> put_flash(:nav, :no_access)
       |> push_navigate(to: "/projects")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(page_title: "Connected Systems", connected_system: nil)
  end

  defp apply_action(socket, :new, _params) do
    connected_system = %ConnectedSystem{}

    socket
    |> assign(
      page_title: "New Connected System",
      connected_system: connected_system,
      form: to_form(ConnectedSystems.change_connected_system(connected_system))
    )
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    connected_system = ConnectedSystems.get_connected_system!(id)

    socket
    |> assign(
      page_title: "Edit Connected System",
      connected_system: connected_system,
      form: to_form(ConnectedSystems.change_connected_system(connected_system))
    )
  end

  @impl true
  def handle_event("validate", %{"connected_system" => params}, socket) do
    changeset =
      socket.assigns.connected_system
      |> ConnectedSystems.change_connected_system(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, form: to_form(changeset))}
  end

  def handle_event("save", %{"connected_system" => params}, socket) do
    save_connected_system(socket, socket.assigns.live_action, params)
  end

  def handle_event("delete", %{"id" => id}, socket) do
    connected_system = ConnectedSystems.get_connected_system!(id)

    case ConnectedSystems.delete_connected_system(connected_system) do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Connected system deleted")
         |> push_navigate(to: ~p"/settings/connected-systems")}

      {:error, reason} ->
        Logger.error("Error deleting connected system: #{inspect(reason)}")

        {:noreply,
         socket
         |> put_flash(:error, "Couldn't delete connected system")
         |> push_navigate(to: ~p"/settings/connected-systems")}
    end
  end

  defp save_connected_system(socket, :new, params) do
    params = Map.put(params, "created_by_id", socket.assigns.current_user.id)

    case ConnectedSystems.create_connected_system(params) do
      {:ok, _connected_system} ->
        {:noreply,
         socket
         |> put_flash(:info, "Connected system created")
         |> push_navigate(to: ~p"/settings/connected-systems")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  defp save_connected_system(socket, :edit, params) do
    case ConnectedSystems.update_connected_system(
           socket.assigns.connected_system,
           params
         ) do
      {:ok, _connected_system} ->
        {:noreply,
         socket
         |> put_flash(:info, "Connected system updated")
         |> push_navigate(to: ~p"/settings/connected-systems")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, form: to_form(changeset))}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header current_user={@current_user}>
          <:title>{@page_title}</:title>
          <.link patch={~p"/settings/connected-systems/new"}>
            <.button theme="primary" id="new-connected-system-button">
              <.icon name="hero-plus" class="h-4 w-4 mr-1" /> New System
            </.button>
          </.link>
        </LayoutComponents.header>
      </:header>
      <LayoutComponents.centered>
        <%= if @connected_systems == [] do %>
          <.empty_state
            icon="hero-plus-circle"
            message="No connected systems yet."
            button_text="Add your first system"
            button_id="empty-new-connected-system-button"
            button_click={JS.patch(~p"/settings/connected-systems/new")}
            button_disabled={false}
          />
        <% else %>
          <.table id="connected-systems">
            <:header>
              <.tr>
                <.th>Name</.th>
                <.th>Type</.th>
                <.th>Actions</.th>
              </.tr>
            </:header>
            <:body>
              <.tr :for={system <- @connected_systems} id={"system-#{system.id}"}>
                <.td class="font-medium">{system.name}</.td>
                <.td>{system.type}</.td>
                <.td>
                  <div class="flex gap-2">
                    <.link
                      patch={~p"/settings/connected-systems/#{system.id}/edit"}
                      class="text-indigo-600 hover:text-indigo-900"
                      id={"edit-system-#{system.id}"}
                    >
                      Edit
                    </.link>
                    <.link
                      phx-click="delete"
                      phx-value-id={system.id}
                      data-confirm={"Are you sure you want to delete #{system.name}? Credentials referencing it will keep working but lose the reference."}
                      class="text-red-600 hover:text-red-900"
                      id={"delete-system-#{system.id}"}
                    >
                      Delete
                    </.link>
                  </div>
                </.td>
              </.tr>
            </:body>
          </.table>
        <% end %>

        <.modal
          :if={@live_action in [:new, :edit]}
          id="connected-system-modal"
          show={true}
          on_close={JS.patch(~p"/settings/connected-systems")}
          width="max-w-md"
        >
          <:title>{@page_title}</:title>
          <.form
            for={@form}
            id="connected-system-form"
            phx-change="validate"
            phx-submit="save"
          >
            <div class="space-y-4">
              <.input
                field={@form[:name]}
                type="text"
                label="Name"
                placeholder="Southwest Regional Health Tracker"
              />
              <.input
                field={@form[:type]}
                type="text"
                label="Type"
                placeholder="DHIS2, Postgres, Custom…"
              />
            </div>
            <.modal_footer>
              <.button type="submit" theme="primary" id="save-connected-system">
                Save
              </.button>
              <.button
                type="button"
                theme="secondary"
                phx-click={JS.patch(~p"/settings/connected-systems")}
              >
                Cancel
              </.button>
            </.modal_footer>
          </.form>
        </.modal>
      </LayoutComponents.centered>
    </LayoutComponents.page_content>
    """
  end
end
