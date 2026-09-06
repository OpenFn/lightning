defmodule LightningWeb.CollectionLive.Index do
  use LightningWeb, :live_view

  on_mount {LightningWeb.Hooks, :ensure_admin}

  import LightningWeb.CollectionLive.Components

  alias Lightning.Collections
  alias Lightning.Collections.Collection

  require Logger

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(
       page_title: "Collections",
       active_menu_item: :collections,
       collections: Collections.list_collections(),
       sort_by: "name",
       sort_direction: :asc
     ), layout: {LightningWeb.Layouts, :settings}}
  end

  @impl true
  def handle_event("sort", %{"by" => field}, socket)
      when field in ~w(name byte_size_sum) do
    new_direction =
      if socket.assigns.sort_by == field do
        switch_sort_direction(socket.assigns.sort_direction)
      else
        :asc
      end

    collections =
      Collections.list_collections(
        order_by: [{new_direction, String.to_existing_atom(field)}]
      )

    {:noreply,
     socket
     |> assign(:collections, collections)
     |> assign(:sort_by, field)
     |> assign(:sort_direction, new_direction)}
  end

  def handle_event("delete_collection", %{"collection" => collection_id}, socket) do
    case Collections.delete_collection(collection_id) do
      {:ok, _collection} ->
        {:noreply,
         socket
         |> put_flash(:info, "Collection deleted")
         |> push_navigate(to: ~p"/settings/collections")}

      {:error, reason} ->
        Logger.error("Error during collection deletion: #{inspect(reason)}")

        {:noreply,
         socket
         |> put_flash(:error, "Couldn't delete collection!")
         |> push_navigate(to: ~p"/settings/collections")}
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
          <.collections_table
            collections={@collections}
            user={@current_user}
            sort_by={@sort_by}
            sort_direction={@sort_direction}
          >
            <:empty_state>
              <.empty_state
                icon="hero-plus-circle"
                message="No collection found."
                button_text="Create a new one."
                button_id="open-create-collection-modal-big-buttton"
                button_click={show_modal("create-collection-modal")}
                button_disabled={false}
              />
            </:empty_state>
            <:create_collection_button>
              <.button
                role="button"
                id="open-create-collection-modal-button"
                phx-click={show_modal("create-collection-modal")}
                class="col-span-1 w-full"
                theme="primary"
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
