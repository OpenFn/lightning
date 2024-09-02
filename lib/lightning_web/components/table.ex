defmodule LightningWeb.Components.Table do
  @moduledoc false

  use Phoenix.Component

  @doc ~S"""
  Renders a table with generic styling.

  ## Examples

      <.table id="users" rows={@users}>
        <:col :let={user} label="id"><%= user.id %></:col>
        <:col :let={user} label="username"><%= user.username %></:col>
      </.table>
  """

  attr :id, :string, required: true
  attr :row_click, :any, default: nil
  attr :rows, :list, required: true
  attr :row_class, :string, default: ""

  slot :col, required: true do
    attr :label, :string
    attr :label_class, :string
  end

  slot :action, doc: "the slot for showing user actions in the last table column"

  def table(assigns) do
    ~H"""
    <div
      id={@id}
      class="overflow-hidden shadow ring-1 ring-black ring-opacity-5 sm:rounded-lg"
    >
      <table class="min-w-full divide-y divide-gray-300">
        <thead class="">
          <tr>
            <th
              :for={col <- @col}
              scope="col"
              class="px-3 py-3.5 text-left text-sm font-semibold text-gray-500"
            >
              <div class={col[:label_class]}>
                <%= col[:label] %>
              </div>
            </th>
            <th
              :if={@action != []}
              scope="col"
              class="relative py-3.5 pl-3 pr-4 sm:pr-6"
            >
              <span class="sr-only">Actions</span>
            </th>
          </tr>
        </thead>
        <tbody class="divide-y divide-gray-200 bg-white">
          <tr
            :for={row <- @rows}
            id={"#{@id}-#{Phoenix.Param.to_param(row)}"}
            class={[@row_class]}
          >
            <td
              :for={col <- @col}
              phx-click={@row_click && @row_click.(row)}
              class={[
                "whitespace-nowrap px-3 py-4 text-sm text-gray-500",
                @row_click && "hover:cursor-pointer"
              ]}
            >
              <%= render_slot(col, row) %>
            </td>
            <td :if={@action != []} class="p-0 w-14">
              <div class="relative whitespace-nowrap py-2 text-right text-sm font-medium">
                <span
                  :for={action <- @action}
                  class="relative ml-4 font-semibold leading-6 text-zinc-900 hover:text-zinc-700"
                >
                  <%= render_slot(action, row) %>
                </span>
              </div>
            </td>
          </tr>
        </tbody>
      </table>
    </div>
    """
  end
end
