defmodule LightningWeb.CollectionLive.Index do
  require Logger
  alias Lightning.Collections.Collection
  use LightningWeb, :live_view

  import LightningWeb.CollectionLive.Components

  alias Lightning.Collections
  alias Lightning.Policies.Users
  alias Lightning.Policies.Permissions

  def mount(_params, _session, socket) do
    can_access_admin_space =
      Users
      |> Permissions.can?(:access_admin_space, socket.assigns.current_user, {})

    if can_access_admin_space do
      {:ok,
       socket
       |> assign(
         page_title: "Collections",
         active_menu_item: :collections,
         collections: Collections.list_collections(),
         name_sort_direction: :asc
       ), layout: {LightningWeb.Layouts, :settings}}
    else
      {:ok,
       socket
       |> put_flash(:nav, :no_access)
       |> push_redirect(to: "/projects")}
    end
  end

  def handle_event("delete_collection", %{"collection" => collection_id}, socket) do
    case Collections.delete_collection(collection_id) do
      {:ok, _collection} ->
        {:noreply,
         socket
         |> put_flash(:info, "Collection deleted successfully!")
         |> push_navigate(to: ~p"/settings/collections")}

      {:error, reason} ->
        Logger.error("Error during collection deletion: #{inspect(reason)}")

        {:noreply,
         socket
         |> put_flash(:error, "Couldn't delete collection!")
         |> push_navigate(to: ~p"/settings/collections")}
    end
  end

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
          <.collections_table
            collections={@collections}
            user={@current_user}
            name_direction={@name_sort_direction}
          >
            <:empty_state>
              <button
                type="button"
                id="open-create-collection-modal-big-buttton"
                phx-click={show_modal("create-collection-modal")}
                class="relative block w-full rounded-lg border-2 border-dashed border-gray-300 p-4 text-center hover:border-gray-400 focus:outline-none"
              >
                <Heroicons.plus_circle class="mx-auto w-12 h-12 text-secondary-400" />
                <span class="mt-2 block text-xs font-semibold text-secondary-600">
                  No collection found. Create a new one.
                </span>
              </button>
            </:empty_state>
            <:create_collection_button>
              <.button
                role="button"
                id="open-create-collection-modal-button"
                phx-click={show_modal("create-collection-modal")}
                class="col-span-1 w-full rounded-md"
              >
                Create collection
              </.button>
            </:create_collection_button>
          </.collections_table>
          <.live_component
            id="create-collection-modal"
            module={LightningWeb.CollectionLive.CollectionCreationModal}
            collection={%Collection{}}
            return_to={~p"/settings/collections"}
          />
        </div>
      </LayoutComponents.centered>
    </LayoutComponents.page_content>
    """
  end
end
