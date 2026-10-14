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

  @avatar_cases [
    %{
      title: "Initials",
      type: "initials",
      first_name: "Ada",
      last_name: "Lovelace"
    },
    %{title: "First name only", type: "first-name", first_name: "Ada"},
    %{title: "Image", type: "image", src: "/images/user.png"},
    %{
      title: "Broken image",
      type: "broken-image",
      first_name: "Ada",
      last_name: "Lovelace",
      src: "/images/missing.png"
    },
    %{title: "Icon", type: "icon", icon: "hero-rocket-launch"},
    %{title: "No name", type: "no-name"}
  ]

  @impl true
  def render(assigns) do
    assigns =
      assign(assigns, cases: @cases, tabs: @tabs, avatar_cases: @avatar_cases)

    ~H"""
    <div class="mx-auto max-w-7xl px-4 sm:px-6 lg:px-8 py-6 flex flex-col gap-y-6">
      <h2 class="text-xl font-bold">Components</h2>
      <div id="avatar-showcase" class="overflow-hidden rounded-md bg-white shadow">
        <div class="px-6 py-4">
          <h3 class="text-lg font-bold">Avatar</h3>
          <p class="font-mono text-xs text-gray-500">
            Styling: assets/css/ui/avatar.css
          </p>
        </div>
        <div
          :for={c <- @avatar_cases}
          class="grid grid-cols-2 gap-x-8 border-t border-gray-200 px-6 py-4"
        >
          <div>
            <p class="mb-2 text-xs text-gray-400">LiveView, {c.title}</p>
            <div class="flex items-center gap-4">
              <.avatar
                :for={size <- ~w(large medium small)}
                size={size}
                first_name={c[:first_name]}
                last_name={c[:last_name]}
                src={c[:src]}
                icon={c[:icon] || "hero-user"}
              />
            </div>
          </div>
          <div>
            <p class="mb-2 text-xs text-gray-400">React, {c.title}</p>
            <div
              id={"react-avatar-#{c.type}"}
              phx-hook="ReactComponent"
              phx-update="ignore"
              data-react-name="AvatarShowcase"
              data-react-file={~p"/assets/js/dev/AvatarShowcase.js"}
              data-type={c.type}
            >
            </div>
          </div>
        </div>
      </div>
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
    </div>
    """
  end
end
