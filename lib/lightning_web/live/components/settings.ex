defmodule LightningWeb.Components.Settings do
  @moduledoc false
  use LightningWeb, :component

  def menu_item(assigns) do
    base_classes = ~w[px-3 py-2 rounded-md text-sm font-medium rounded-md block]

    active_classes = ~w[text-primary-200 bg-primary-900] ++ base_classes

    inactive_classes = ~w[text-primary-300 hover:bg-primary-900] ++ base_classes

    assigns =
      assigns
      |> assign(
        class:
          if assigns[:active] do
            active_classes
          else
            inactive_classes
          end
      )

    ~H"""
    <div class="h-12 mx-4">
      <.link navigate={@to} class={@class}>
        <%= if assigns[:inner_block] do %>
          <%= render_slot(@inner_block) %>
        <% else %>
          <%= @text %>
        <% end %>
      </.link>
    </div>
    """
  end
end
