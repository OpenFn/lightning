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

  @cases [
    %{title: "Underline", variant: "underline", size: "default"},
    %{title: "Underline, small", variant: "underline", size: "small"},
    %{title: "Pills", variant: "pills", size: "default"},
    %{title: "Pills, small", variant: "pills", size: "small"},
    %{title: "Icons", variant: "underline", size: "default", icons: true},
    %{title: "Icons, small", variant: "underline", size: "small", icons: true},
    %{title: "Vertical", variant: "underline", orientation: "vertical"}
  ]

  @tabs [
    {"log", "Log", "hero-document-text"},
    {"input", "Input", "hero-arrow-down-on-square"},
    {"output", "Output", "hero-arrow-up-on-square"}
  ]

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns,
        cases: @cases,
        tabs: @tabs,
        badge_colors: ~w(neutral success warning danger info brand orange dark)
      )

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
          :for={{c, index} <- Enum.with_index(@cases)}
          class="grid grid-cols-2 gap-x-8 border-t border-gray-200 px-6 py-4"
        >
          <div>
            <p class="mb-2 text-xs text-gray-400">LiveView, {c.title}</p>
            <.tabs
              id={"heex-tabs-#{index}"}
              variant={c.variant}
              size={Map.get(c, :size, "default")}
              orientation={Map.get(c, :orientation, "horizontal")}
              active={@tab}
            >
              <:tab
                :for={{id, label, icon} <- @tabs}
                id={id}
                patch={"/dev/components?tab=#{id}"}
                icon={if Map.get(c, :icons), do: icon}
              >
                {label}
              </:tab>
            </.tabs>
            <p class="py-3">{String.capitalize(@tab)} content</p>
          </div>
          <div>
            <p class="mb-2 text-xs text-gray-400">React, {c.title}</p>
            <div
              id={"react-tabs-#{index}"}
              phx-hook="ReactComponent"
              phx-update="ignore"
              data-react-name="TabsShowcase"
              data-react-file={~p"/assets/js/dev/TabsShowcase.js"}
              data-variant={c.variant}
              data-size={Map.get(c, :size, "default")}
              data-orientation={Map.get(c, :orientation, "horizontal")}
              data-icons={to_string(Map.get(c, :icons, false))}
            >
            </div>
          </div>
        </div>
        <div class="grid grid-cols-2 gap-x-8 border-t border-gray-200 px-6 py-4">
          <div>
            <p class="mb-2 text-xs text-gray-400">
              LiveView, hash mode with a disabled tab
            </p>
            <.tabs id="heex-tabs-hash" default_hash="log">
              <:tab hash="log">Log</:tab>
              <:tab hash="input" disabled={true} disabled_reason="Pick a step">
                Input
              </:tab>
              <:tab hash="output">Output</:tab>
              <:panel :for={{hash, label, _icon} <- @tabs} hash={hash}>
                <p class="py-3">{label} content</p>
              </:panel>
            </.tabs>
          </div>
          <div>
            <p class="mb-2 text-xs text-gray-400">
              React, disabled tab
            </p>
            <div
              id="react-tabs-disabled"
              phx-hook="ReactComponent"
              phx-update="ignore"
              data-react-name="TabsShowcase"
              data-react-file={~p"/assets/js/dev/TabsShowcase.js"}
              data-variant="underline"
              data-size="default"
              data-orientation="horizontal"
              data-icons="false"
              data-disabled="true"
            >
            </div>
          </div>
        </div>
      </div>
      <div class="overflow-hidden rounded-md bg-white shadow">
        <div class="px-6 py-4">
          <h3 class="text-lg font-bold">Badge</h3>
          <p class="font-mono text-xs text-gray-500">
            Styling: assets/css/ui/badge.css
          </p>
        </div>
        <div class="grid grid-cols-2 gap-x-8 border-t border-gray-200 px-6 py-4">
          <div class="flex flex-col gap-y-3">
            <p class="text-xs text-gray-400">LiveView</p>
            <div class="flex flex-wrap items-center gap-2">
              <.badge :for={color <- @badge_colors} color={color}>{color}</.badge>
            </div>
            <div class="flex flex-wrap items-center gap-2">
              <.badge :for={color <- @badge_colors} color={color} size="small">
                {color}
              </.badge>
            </div>
            <div class="flex flex-wrap items-center gap-2">
              <.badge mono>a1b2c3d</.badge>
              <.badge color="success" icon="hero-bolt">Webhook</.badge>
              <.badge class="max-w-32">
                <span class="truncate">a-very-long-sandbox-name</span>
              </.badge>
              <.badge color="brand">
                Project A <:remove label="Remove Project A" />
              </.badge>
            </div>
            <div class="flex flex-wrap items-center gap-4">
              <.badge :for={color <- @badge_colors} color={color} dot>
                {color}
              </.badge>
              <.badge color="info" dot pulse>Running</.badge>
            </div>
          </div>
          <div>
            <p class="mb-2 text-xs text-gray-400">React</p>
          </div>
        </div>
      </div>
    </div>
    """
  end
end
