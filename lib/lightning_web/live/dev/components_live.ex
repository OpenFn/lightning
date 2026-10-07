defmodule LightningWeb.Dev.ComponentsLive do
  # Internal Development Page for viewing and working on components.
  # Access this page at /dev/components
  @moduledoc false
  use LightningWeb, {:live_view, layout: {LightningWeb.Layouts, :blank}}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    {:noreply, assign(socket, :tab, Map.get(params, "tab", "log"))}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-6 flex flex-col gap-y-6">
      <h2 class="text-xl font-bold">Components</h2>
      <div class="overflow-hidden rounded-md bg-white shadow">
        <div class="px-6 py-4">
          <h3 class="text-lg font-bold">Tabs</h3>
          <p class="font-mono text-xs text-gray-500">
            Styling: assets/css/ui/tabs.css
          </p>
        </div>
        <div
          :for={size <- ~w(default small)}
          class="grid grid-cols-2 gap-x-8 border-t border-gray-200 px-6 py-4"
        >
          <div>
            <p class="mb-2 text-xs text-gray-400">LiveView, size {size}</p>
            <.tabs id={"heex-tabs-#{size}"} size={size} active={@tab}>
              <:tab
                :for={
                  {id, label} <- [
                    {"log", "Log"},
                    {"input", "Input"},
                    {"output", "Output"}
                  ]
                }
                id={id}
                patch={"/dev/components?tab=#{id}"}
              >
                {label}
              </:tab>
            </.tabs>
            <p class="py-3">{String.capitalize(@tab)} content</p>
          </div>
          <div>
            <p class="mb-2 text-xs text-gray-400">React, size {size}</p>
            <div
              id={"react-tabs-#{size}"}
              phx-hook="ReactComponent"
              phx-update="ignore"
              data-react-name="TabsShowcase"
              data-react-file={~p"/assets/js/dev/TabsShowcase.js"}
              data-size={size}
            >
            </div>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
