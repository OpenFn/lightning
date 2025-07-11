defmodule LightningWeb.RunLive.ExampleMiniUsage do
  @moduledoc """
  Example showing how to integrate the mini history component into another LiveView.
  This could be used in dashboards, workflow editors, or any other view that needs
  a compact history overview.
  """
  use LightningWeb, :live_view

  alias Lightning.WorkOrders

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, %{assigns: %{project: project}} = socket) do
    # Subscribe to work order events for real-time updates
    WorkOrders.subscribe(project.id)

    {:ok,
     socket
     |> assign(
       page_title: "Dashboard with Mini History",
       selected_run_id: nil,
       active_menu_item: :runs
     )}
  end

  @impl true
  def handle_info({:run_selected, run_id}, socket) do
    # Handle when a run is selected from the mini history
    # This could trigger loading run details, opening a sidebar, etc.
    {:noreply, assign(socket, selected_run_id: run_id)}
  end

  @impl true
  def handle_info(%Lightning.WorkOrders.Events.WorkOrderCreated{}, socket) do
    # Refresh the mini history component when new work orders are created
    send_update(LightningWeb.RunLive.MiniIndex, id: "mini-history", action: :refresh)
    {:noreply, socket}
  end

  @impl true
  def handle_info(%Lightning.WorkOrders.Events.WorkOrderUpdated{}, socket) do
    # Refresh the mini history component when work orders are updated
    send_update(LightningWeb.RunLive.MiniIndex, id: "mini-history", action: :refresh)
    {:noreply, socket}
  end

  @impl true
  def handle_info(%mod{}, socket)
      when mod in [Lightning.WorkOrders.Events.RunCreated, Lightning.WorkOrders.Events.RunUpdated] do
    # Refresh the mini history component when runs are created/updated
    send_update(LightningWeb.RunLive.MiniIndex, id: "mini-history", action: :refresh)
    {:noreply, socket}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header current_user={@current_user} project={@project}>
          <:title>{@page_title}</:title>
        </LayoutComponents.header>
      </:header>

      <LayoutComponents.centered>
        <div class="grid grid-cols-1 lg:grid-cols-3 gap-6">
          <!-- Main Content Area -->
          <div class="lg:col-span-2">
            <div class="bg-white shadow-sm rounded-lg p-6">
              <h2 class="text-lg font-medium text-gray-900 mb-4">Main Dashboard Content</h2>

              <%= if @selected_run_id do %>
                <div class="p-4 bg-blue-50 rounded-lg mb-4">
                  <p class="text-sm text-blue-800">
                    Selected run: <span class="font-mono">{@selected_run_id}</span>
                  </p>
                  <p class="text-xs text-blue-600 mt-1">
                    This is where you would show run details, visualizations, etc.
                  </p>
                </div>
              <% else %>
                <p class="text-gray-500">Select a run from the history panel to see details.</p>
              <% end %>

              <div class="space-y-4">
                <div class="h-32 bg-gray-100 rounded flex items-center justify-center">
                  <span class="text-gray-500">Workflow Diagram</span>
                </div>
                <div class="h-24 bg-gray-100 rounded flex items-center justify-center">
                  <span class="text-gray-500">Stats Panel</span>
                </div>
              </div>
            </div>
          </div>

          <!-- Mini History Sidebar -->
          <div class="lg:col-span-1">
            <.live_component
              module={LightningWeb.RunLive.MiniIndex}
              id="mini-history"
              project={@project}
            />
          </div>
        </div>
      </LayoutComponents.centered>
    </LayoutComponents.page_content>
    """
  end
end
