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
            variant="secondary"
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
          <span class="font-medium">{@collection.name}</span>
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
          phx-disable-with="Deleting..."
          theme="danger"
        >
          Delete
        </.button>
        <.button type="button" phx-click={hide_modal(@id)} theme="secondary">
          Cancel
        </.button>
      </div>
    </.modal>
    """
  end

  defp table_title(assigns) do
    ~H"""
    <h3 class="text-3xl font-bold">
      Collections
      <span class="text-base font-normal">
        ({@count})
      </span>
    </h3>
    """
  end

  # TODO - replace with common table when moving to project scope!
  def collections_table(assigns) do
    assigns =
      assign(assigns,
        collections_count: Enum.count(assigns.collections),
        empty?: Enum.empty?(assigns.collections)
      )

    ~H"""
    <%= if @empty? do %>
      {render_slot(@empty_state)}
    <% else %>
      <div class="mt-5 flex justify-between mb-3">
        <.table_title count={@collections_count} />
        <div>
          {render_slot(@create_collection_button)}
        </div>
      </div>
      <div id="collections-table">
        <.table>
          <.tr>
            <.th>
              <Common.sortable_table_header
                phx-click="sort"
                phx-value-by="name"
                active={true}
                sort_direction={to_string(@name_direction)}
              >
                Name
              </Common.sortable_table_header>
            </.th>
            <.th>Project</.th>
            <.th>Used Storage (MB)</.th>
            <.th></.th>
          </.tr>

          <.tr
            :for={collection <- @collections}
            id={"collections-table-row-#{collection.id}"}
            class="hover:bg-gray-100 transition-colors duration-200"
          >
            <.td class="break-words max-w-[15rem] text-gray-800">
              {collection.name}
            </.td>
            <.td class="break-words max-w-[25rem]">
              {collection.project.name}
            </.td>
            <.td class="break-words max-w-[25rem]">
              {div(collection.byte_size_sum, 1_000_000)}
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
      </div>
    <% end %>
    """
  end
end
