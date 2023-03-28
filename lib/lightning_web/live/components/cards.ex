defmodule LightningWeb.Components.Cards do
  @moduledoc false
  use LightningWeb, :component

  slot :inner_block, required: true

  slot :action,
    required: false,
    doc: "A list of elements to be placed at the bottom of the component"

  def card(assigns) do
    ~H"""
    <div class="col-span-1 flex flex-col divide-y divide-gray-200 rounded-lg bg-white text-center shadow">
      <div class="flex flex-1 flex-col p-8">
        <%= render_slot(@inner_block) %>
      </div>

      <div class="-mt-px flex divide-x divide-gray-200">
        <%= for { action, index } <- @action |> Enum.with_index() do %>
          <div class={"#{if index > 0, do: "-ml-px"} flex w-0 flex-1"}>
            <%= render_slot(action) %>
          </div>
        <% end %>
      </div>
    </div>
    """
  end
end
