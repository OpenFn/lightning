defmodule LightningWeb.ConnectedSystemLive.Components do
  @moduledoc false
  use LightningWeb, :component

  defp confirm_connected_system_deletion_modal(assigns) do
    ~H"""
    <.modal id={@id} width="max-w-md">
      <:title>
        <div class="flex justify-between">
          <span class="font-bold">
            Delete system
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
      <div>
        <p class="text-sm text-gray-500">
          Are you sure you want to delete the system
          <span class="font-medium">{@connected_system.name}</span>
          ? Credentials attached to it will be kept, but they will no longer
          reference this system.<br /><br />
        </p>
      </div>
      <.modal_footer>
        <.button
          id={"#{@id}_confirm_button"}
          type="button"
          phx-click="delete_connected_system"
          phx-value-connected_system={@connected_system.id}
          phx-disable-with="Deleting..."
          theme="danger"
        >
          Delete
        </.button>
        <.button type="button" phx-click={hide_modal(@id)} theme="secondary">
          Cancel
        </.button>
      </.modal_footer>
    </.modal>
    """
  end

  defp table_title(assigns) do
    ~H"""
    <h3 class="text-3xl font-bold">
      Systems
      <span class="text-base font-normal">
        ({@count})
      </span>
    </h3>
    """
  end

  def connected_systems_table(assigns) do
    assigns =
      assign(assigns,
        connected_systems_count: Enum.count(assigns.connected_systems),
        empty?: Enum.empty?(assigns.connected_systems)
      )

    ~H"""
    <%= if @empty? do %>
      {render_slot(@empty_state)}
    <% else %>
      <div class="mt-5 flex justify-between mb-3">
        <.table_title count={@connected_systems_count} />
        <div>
          {render_slot(@create_connected_system_button)}
        </div>
      </div>
      <div>
        <.table id="connected-systems-table">
          <:header>
            <.tr>
              <.th
                sortable={true}
                sort_by="name"
                active={@sort_by == "name"}
                sort_direction={to_string(@sort_direction)}
              >
                Name
              </.th>
              <.th
                sortable={true}
                sort_by="type"
                active={@sort_by == "type"}
                sort_direction={to_string(@sort_direction)}
              >
                Type
              </.th>
              <.th></.th>
            </.tr>
          </:header>
          <:body>
            <%= for connected_system <- @connected_systems do %>
              <.tr id={"connected-systems-table-row-#{connected_system.id}"}>
                <.td class="wrap-break-word max-w-[25rem] text-gray-800">
                  {connected_system.name}
                </.td>
                <.td class="wrap-break-word max-w-[20rem]">
                  {connected_system.type || "—"}
                </.td>
                <.td>
                  <div class="text-right">
                    <button
                      id={"edit-connected-system-#{connected_system.id}-button"}
                      phx-click={
                        show_modal(
                          "update-connected-system-#{connected_system.id}-modal"
                        )
                      }
                      class="table-action"
                    >
                      Edit
                    </button>
                    <button
                      id={"delete-connected-system-#{connected_system.id}-button"}
                      phx-click={
                        show_modal(
                          "delete-connected-system-#{connected_system.id}-modal"
                        )
                      }
                      class="table-action"
                    >
                      Delete
                    </button>
                  </div>
                  <.live_component
                    id={"update-connected-system-#{connected_system.id}-modal"}
                    module={
                      LightningWeb.ConnectedSystemLive.ConnectedSystemFormModal
                    }
                    connected_system={connected_system}
                    mode={:update}
                    return_to={~p"/settings/connected_systems"}
                  />
                  <.confirm_connected_system_deletion_modal
                    id={"delete-connected-system-#{connected_system.id}-modal"}
                    connected_system={connected_system}
                  />
                </.td>
              </.tr>
            <% end %>
          </:body>
        </.table>
      </div>
    <% end %>
    """
  end
end
