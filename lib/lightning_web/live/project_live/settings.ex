alias Phoenix.LiveView.JS

defmodule LightningWeb.ProjectLive.Settings do
  @moduledoc """
  Index Liveview for Runs
  """
  use LightningWeb, :live_view

  on_mount({LightningWeb.Hooks, :project_scope})

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(active_menu_item: :settings)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, socket |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket |> assign(:page_title, "Projects settings")
  end

  def tab_bar(assigns) do
    ~H"""
    <div
      id={"tab-bar-#{@id}"}
      class="flex gap-x-8 gap-y-2 border-b border-gray-200 dark:border-gray-600"
      data-active-classes="border-b-2 border-primary-500 text-primary-600"
      data-inactive-classes="border-b-2 border-transparent text-gray-500 hover:border-gray-300 hover:text-gray-600 hover:border-gray-300"
      data-default-hash={@default_hash}
      phx-hook="TabSelector"
    >
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  attr(:for_hash, :string, required: true)
  slot(:inner_block, required: true)

  def panel_content(assigns) do
    ~H"""
    <div
      class="h-[calc(100%-0.75rem)]"
      data-panel-hash={@for_hash}
      style="display: none;"
      lv-keep-style
    >
      <%= render_slot(@inner_block) %>
    </div>
    """
  end

  def tab_item(assigns) do
    ~H"""
    <a
      id={"tab-item-#{@hash}"}
      class="whitespace-nowrap flex items-center py-3 px-3 font-medium
             text-sm border-b-2 border-transparent text-gray-500
             hover:border-gray-300 hover:text-gray-600 hover:border-gray-300"
      data-hash={@hash}
      lv-keep-class
      phx-click={switch_tabs(@hash)}
      href={"##{@hash}"}
    >
      <%= render_slot(@inner_block) %>
    </a>
    """
  end

  defp switch_tabs(hash) do
    JS.hide(to: "[data-panel-hash]:not([data-panel-hash=#{hash}])")
    |> JS.show(
      to: "[data-panel-hash=#{hash}]",
      transition: {"ease-out duration-300", "opacity-0", "opacity-100"},
      time: 300
    )
  end
end
