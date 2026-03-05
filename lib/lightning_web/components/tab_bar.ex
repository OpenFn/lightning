defmodule LightningWeb.Components.TabBar do
  use Phoenix.Component

  @doc """
  Renders a pill-style tab bar, matching the React `Tabs.tsx` component style.

  ## Examples

      <.pill_tabs id="history-tabs" active="work-orders">
        <:tab id="work-orders" patch={~p"/projects/\#{@project}/history"}>
          Work Orders
        </:tab>
        <:tab id="channel-logs" patch={~p"/projects/\#{@project}/history/channels"}>
          Channel Logs
        </:tab>
      </.pill_tabs>
  """
  attr :id, :string, required: true
  attr :active, :string, required: true

  slot :tab, required: true do
    attr :id, :string, required: true
    attr :patch, :string, required: true
  end

  def pill_tabs(assigns) do
    ~H"""
    <div id={@id} class="bg-slate-100 p-1 rounded-lg">
      <nav class="flex gap-1" aria-label="Tabs">
        <.link
          :for={tab <- @tab}
          patch={tab.patch}
          class={[
            "rounded-md px-3 py-2 text-sm font-medium transition-all duration-200",
            if(tab.id == @active,
              do: "bg-white text-indigo-600",
              else: "text-gray-500 hover:text-gray-700 hover:bg-slate-50"
            )
          ]}
        >
          {render_slot(tab)}
        </.link>
      </nav>
    </div>
    """
  end
end
