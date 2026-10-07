defmodule LightningWeb.Components.UI.Tabs do
  @moduledoc false
  # Tabs as links: each tab patches to a URL, and the page shows the content
  # for the current one. Styled by .ui-tabs/.ui-tab in assets/css/ui/tabs.css,
  # the same classes assets/js/ui/Tabs.tsx uses.
  use Phoenix.Component

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
  """
  attr :id, :string, required: true
  attr :variant, :string, values: ~w(underline pills), default: "underline"
  attr :size, :string, values: ~w(default small), default: "default"

  attr :orientation, :string,
    values: ~w(horizontal vertical),
    default: "horizontal"

  attr :active, :string, default: nil
  attr :class, :any, default: nil

  slot :tab, required: true do
    attr :id, :string, required: true
    attr :patch, :string, required: true
  end

  def tabs(assigns) do
    ~H"""
    <nav
      id={@id}
      aria-label="Tabs"
      class={[
        "ui-tabs",
        @variant == "pills" && "ui-tabs--pills",
        @size == "small" && "ui-tabs--small",
        @orientation == "vertical" && "ui-tabs--vertical",
        @class
      ]}
    >
      <.link
        :for={tab <- @tab}
        patch={tab.patch}
        aria-current={tab.id == @active && "page"}
        class="ui-tab"
      >
        {render_slot(tab)}
      </.link>
    </nav>
    """
  end
end
