defmodule LightningWeb.Components.UI.Tabs do
  @moduledoc false
  # Two modes, styled by .ui-tabs/.ui-tab in assets/css/ui/tabs.css, the same
  # classes assets/js/ui/Tabs.tsx uses.
  # - Patch mode: each tab patches to a URL, and the page shows the content for
  #   the current one.
  # - Hash mode (when :panel slots are given): the TabbedContainer hook shows
  #   the panel for the URL hash. Its markup must match what the hook reads.
  use Phoenix.Component

  import LightningWeb.Components.Icons

  @doc """
  ## Examples

      <.tabs id="history-tabs" variant="pills" active="work-orders">
        <:tab id="work-orders" patch={~p"/projects/\#{@project}/history"}>
          Work Orders
        </:tab>
        <:tab id="channel-logs" patch={~p"/projects/\#{@project}/history/channels"}>
          Channel Logs
        </:tab>
      </.tabs>

      <.tabs id="run-tabs" default_hash="log">
        <:tab hash="log">Log</:tab>
        <:tab hash="input" disabled={true} disabled_reason="Pick a step">Input</:tab>
        <:panel hash="log">...</:panel>
        <:panel hash="input">...</:panel>
      </.tabs>
  """
  attr :id, :string, required: true
  attr :variant, :string, values: ~w(underline pills), default: "underline"
  attr :size, :string, values: ~w(default small), default: "default"

  attr :orientation, :string,
    values: ~w(horizontal vertical),
    default: "horizontal"

  attr :active, :string, default: nil
  attr :default_hash, :string, default: nil
  attr :class, :any, default: nil

  slot :tab, required: true do
    attr :id, :string
    attr :patch, :string
    attr :hash, :string
    attr :disabled, :boolean
    attr :disabled_reason, :string
    attr :icon, :string
  end

  slot :panel do
    attr :hash, :string, required: true
    attr :class, :string
  end

  def tabs(%{panel: [_ | _]} = assigns) do
    ~H"""
    <div
      id={@id}
      class={[
        if(@orientation == "vertical",
          do: "flex flex-row gap-y-2 tab-container",
          else: "flex flex-col gap-x-4 gap-y-2 tab-container"
        ),
        @class
      ]}
      data-default-hash={@default_hash}
      phx-hook="TabbedContainer"
    >
      <div role="tablist" class={list_class(assigns, nil)}>
        <.tab
          :for={tab <- @tab}
          hash={tab[:hash]}
          disabled={tab[:disabled]}
          disabled_reason={tab[:disabled_reason]}
          icon={tab[:icon]}
        >
          {render_slot(tab)}
        </.tab>
      </div>
      <div :if={@orientation == "vertical"} class="grow">
        <.panels panel={@panel} />
      </div>
      <.panels :if={@orientation != "vertical"} panel={@panel} />
    </div>
    """
  end

  def tabs(assigns) do
    ~H"""
    <nav id={@id} aria-label="Tabs" class={list_class(assigns, @class)}>
      <.link
        :for={tab <- @tab}
        patch={tab.patch}
        aria-current={tab.id == @active && "page"}
        class="ui-tab"
      >
        <.icon :if={tab[:icon]} name={tab.icon} class="ui-tab__icon" />
        {render_slot(tab)}
      </.link>
    </nav>
    """
  end

  defp list_class(assigns, class) do
    [
      "ui-tabs",
      assigns.variant == "pills" && "ui-tabs--pills",
      assigns.size == "small" && "ui-tabs--small",
      assigns.orientation == "vertical" && "ui-tabs--vertical",
      class
    ]
  end

  attr :hash, :string, required: true
  attr :disabled, :boolean, default: false
  attr :disabled_reason, :string
  attr :icon, :string, default: nil
  slot :inner_block, required: true

  defp tab(assigns) do
    ~H"""
    <%= if @disabled do %>
      <span
        id={"#{@hash}-tab"}
        aria-controls={"#{@hash}-panel"}
        aria-selected="false"
        class="ui-tab"
        role="tab"
        data-disabled
        data-hash={@hash}
        phx-hook="Tooltip"
        aria-label={@disabled_reason}
        data-allow-html="true"
        lv-keep-aria
      >
        <.icon :if={@icon} name={@icon} class="ui-tab__icon" />
        {render_slot(@inner_block)}
      </span>
    <% else %>
      <a
        id={"#{@hash}-tab"}
        aria-controls={"#{@hash}-panel"}
        aria-selected="false"
        class="ui-tab"
        role="tab"
        data-hash={@hash}
        href={"##{@hash}"}
        lv-keep-aria
      >
        <.icon :if={@icon} name={@icon} class="ui-tab__icon" />
        {render_slot(@inner_block)}
      </a>
    <% end %>
    """
  end

  attr :panel, :list, required: true

  # Horizontal panels sit directly in the flex container, so callers can size
  # them with flex classes; vertical ones share a wrapper beside the tablist.
  defp panels(assigns) do
    ~H"""
    <.panel :for={panel <- @panel} hash={panel.hash} class={panel[:class]}>
      {render_slot(panel)}
    </.panel>
    """
  end

  attr :hash, :string, required: true
  attr :class, :string, default: nil
  slot :inner_block, required: true

  defp panel(assigns) do
    ~H"""
    <div
      id={"#{@hash}-panel"}
      aria-labelledby={"#{@hash}-tab"}
      class={[@class, "hidden"]}
      role="tabpanel"
      tabindex="0"
      lv-keep-class
    >
      {render_slot(@inner_block)}
    </div>
    """
  end
end
