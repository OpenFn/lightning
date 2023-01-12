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
      class="nav nav-tabs flex flex-col flex-wrap list-none mx-4"
      data-active-classes="text-primary-500 bg-secondary-200"
      data-inactive-classes="text-primary-400 hover:bg-secondary-200"
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
      class="nav-link px-3 py-2 rounded-md text-sm font-medium rounded-md block active"
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
