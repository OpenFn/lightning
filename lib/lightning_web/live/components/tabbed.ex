defmodule LightningWeb.Components.Tabbed do
  @moduledoc false
  use LightningWeb, :component

  attr :id, :string, required: true
  attr :default_hash, :string, default: nil
  attr :class, :string, default: ""

  attr :orientation, :string,
    default: "horizontal",
    values: ["horizontal", "vertical"]

  slot :tab, required: true do
    attr :hash, :string, required: true
    attr :disabled, :boolean
  end

  slot :panel, required: true do
    attr :hash, :string, required: true
    attr :class, :string
  end

  def container(%{orientation: "horizontal"} = assigns) do
    assigns =
      assigns
      |> update(:class, fn class ->
        ~w[dark:border-gray-600 flex flex-col gap-x-4 gap-y-2 border-b tab-container]
        |> Enum.concat(List.wrap(class))
      end)

    ~H"""
    <div
      id={@id}
      class={@class}
      data-default-hash={@default_hash}
      phx-hook="TabbedContainer"
    >
      <div role="tablist" class="flex flex-row space-x-4 tabbed-selector">
        <%= for tab <- @tab do %>
          <.tab hash={tab[:hash]} disabled={tab[:disabled]}>
            <%= render_slot(tab) %>
          </.tab>
        <% end %>
      </div>
      <%= for panel <- @panel do %>
        <.panel hash={panel[:hash]} class={panel[:class]}>
          <%= render_slot(panel) %>
        </.panel>
      <% end %>
    </div>
    """
  end

  def container(%{orientation: "vertical"} = assigns) do
    assigns =
      assigns
      |> update(:class, fn class ->
        ~w[flex flex-row gap-y-2 tab-container]
        |> Enum.concat(List.wrap(class))
      end)

    ~H"""
    <div
      id={@id}
      class={@class}
      data-default-hash={@default_hash}
      phx-hook="TabbedContainer"
    >
      <div
        role="tablist"
        class="flex flex-none flex-col space-y-4 pr-8 tabbed-selector"
      >
        <%= for tab <- @tab do %>
          <.tab hash={tab[:hash]} disabled={tab[:disabled]} class="px-4">
            <%= render_slot(tab) %>
          </.tab>
        <% end %>
      </div>
      <div class="flex-grow">
        <%= for panel <- @panel do %>
          <.panel hash={panel[:hash]} class={panel[:class]}>
            <%= render_slot(panel) %>
          </.panel>
        <% end %>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :class, :string, default: "flex flex-row space-x-4"
  attr :default_hash, :string, default: nil

  slot :tab, required: true do
    attr :hash, :string, required: true
    attr :disabled, :boolean
  end

  def tabs(assigns) do
    assigns =
      assigns
      |> update(:class, fn class -> List.wrap(class) ++ ~w[tabbed-selector] end)

    ~H"""
    <div
      data-default-hash={@default_hash}
      phx-hook="TabbedSelector"
      role="tablist"
      class={@class}
      id={@id}
    >
      <%= for tab <- @tab do %>
        <.tab hash={tab[:hash]} disabled={tab[:disabled]}>
          <%= render_slot(tab) %>
        </.tab>
      <% end %>
    </div>
    """
  end

  attr :hash, :string, required: true
  attr :class, :string, default: nil
  attr :disabled, :boolean, default: false
  attr :disabled_msg, :string, default: "Unavailable"
  slot :inner_block, required: true

  def tab(assigns) do
    ~H"""
    <%= if @disabled do %>
      <span
        id={"#{@hash}-tab"}
        aria-controls={"#{@hash}-panel"}
        aria-selected="false"
        class={@class}
        role="tab"
        data-disabled
        data-hash={@hash}
        lv-keep-aria
      >
        <%= render_slot(@inner_block) %>
      </span>
    <% else %>
      <a
        id={"#{@hash}-tab"}
        aria-controls={"#{@hash}-panel"}
        aria-selected="false"
        class={@class}
        role="tab"
        data-hash={@hash}
        href={"##{@hash}"}
        lv-keep-aria
      >
        <%= render_slot(@inner_block) %>
      </a>
    <% end %>
    """
  end

  attr :hash, :string, required: true
  attr :class, :string, default: "flex"
  slot :inner_block, required: true

  def panel(assigns) do
    assigns =
      assigns |> update(:class, fn class -> List.wrap(class) ++ ~w[hidden] end)

    ~H"""
    <div
      id={"#{@hash}-panel"}
      aria-labelledby={"#{@hash}-tab"}
      class={@class}
      role="tabpanel"
      tabindex="0"
      lv-keep-class
    >
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :default_hash, :string, default: nil
  attr :class, :string, default: "flex"

  slot :panel, required: true do
    attr :hash, :string, required: true
    attr :class, :string
  end

  def panels(assigns) do
    ~H"""
    <div
      id={@id}
      class={@class}
      phx-hook="TabbedPanels"
      data-default-hash={@default_hash}
    >
      <%= for panel <- @panel do %>
        <.panel hash={panel[:hash]} class={panel[:class]}>
          <%= render_slot(panel) %>
        </.panel>
      <% end %>
    </div>
    """
  end
end
