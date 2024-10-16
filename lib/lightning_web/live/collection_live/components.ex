defmodule LightningWeb.CollectionLive.Components do
  use LightningWeb, :component

  import PetalComponents.Table

  defp confirm_collection_deletion_modal(assigns) do
    ~H"""
    <.modal id={@id} width="max-w-md">
      <:title>
        <div class="flex justify-between">
          <span class="font-bold">
            Delete collection
          </span>

          <button
            phx-click={hide_modal(@id)}
            type="button"
            class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
            aria-label={gettext("close")}
          >
            <span class="sr-only">Close</span>
            <Heroicons.x_mark solid class="h-5 w-5 stroke-current" />
          </button>
        </div>
      </:title>
      <div class="px-6">
        <p class="text-sm text-gray-500">
          Are you sure you want to delete the collection
          <span class="font-medium"><%= @collection.name %></span>
          ?
          If you wish to proceed with this action, click on the delete button. To cancel click on the cancel button.<br /><br />
        </p>
      </div>
      <div class="flex flex-row-reverse gap-4 mx-6 mt-2">
        <.button
          id={"#{@id}_confirm_button"}
          type="button"
          phx-click="delete_collection"
          phx-value-collection={@collection.id}
          color_class="bg-red-600 hover:bg-red-700 text-white"
          phx-disable-with="Deleting..."
        >
          Delete
        </.button>
        <button
          type="button"
          phx-click={hide_modal(@id)}
          class="inline-flex items-center rounded-md bg-white px-3.5 py-2.5 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
        >
          Cancel
        </button>
      </div>
    </.modal>
    """
  end

  defp table_title(assigns) do
    ~H"""
    <h3 class="text-3xl font-bold">
      Collections
      <span class="text-base font-normal">
        (<%= @count %>)
      </span>
    </h3>
    """
  end

  def collections_table(assigns) do
    next_sort_icon = %{asc: "hero-chevron-down", desc: "hero-chevron-up"}

    assigns =
      assign(assigns,
        collections_count: Enum.count(assigns.collections),
        empty?: Enum.empty?(assigns.collections),
        name_sort_icon: next_sort_icon[assigns.name_direction]
      )

    ~H"""
    <%= if @empty? do %>
      <%= render_slot(@empty_state) %>
    <% else %>
      <div class="mt-5 flex justify-between mb-3">
        <.table_title count={@collections_count} />
        <div>
          <%= render_slot(@create_collection_button) %>
        </div>
      </div>
      <.table id="collections-table">
        <.tr>
          <.th>
            <div class="group inline-flex items-center">
              Name
              <span
                phx-click="sort"
                phx-value-by="name"
                class="cursor-pointer align-middle ml-2 flex-none rounded text-gray-400 group-hover:visible group-focus:visible"
              >
                <.icon name={@name_sort_icon} />
              </span>
            </div>
          </.th>
          <.th>Project</.th>
          <.th></.th>
        </.tr>

        <.tr
          :for={collection <- @collections}
          id={"collections-table-row-#{collection.id}"}
          class="hover:bg-gray-100 transition-colors duration-200"
        >
          <.td class="break-words max-w-[15rem] text-gray-800">
            <%= collection.name %>
          </.td>
          <.td class="break-words max-w-[25rem]">
            <%= collection.project.name %>
          </.td>

          <.td>
            <div class="text-right">
              <button
                id={"edit-collection-#{collection.id}-button"}
                phx-click={show_modal("update-collection-#{collection.id}-modal")}
                class="table-action"
              >
                Edit
              </button>
              <button
                id={"delete-collection-#{collection.id}-button"}
                phx-click={show_modal("delete-collection-#{collection.id}-modal")}
                class="table-action"
              >
                Delete
              </button>
            </div>
            <.live_component
              id={"update-collection-#{collection.id}-modal"}
              module={LightningWeb.CollectionLive.CollectionCreationModal}
              collection={collection}
              mode={:update}
              return_to={~p"/settings/collections"}
            />
            <.confirm_collection_deletion_modal
              id={"delete-collection-#{collection.id}-modal"}
              collection={collection}
            />
          </.td>
        </.tr>
      </.table>
    <% end %>
    """
  end
end
