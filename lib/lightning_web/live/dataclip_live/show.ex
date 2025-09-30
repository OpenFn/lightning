defmodule LightningWeb.DataclipLive.Show do
  @moduledoc """
  LiveView for showing a single dataclip.
  """
  use LightningWeb, :live_view

  import LightningWeb.Live.MemoryDebug

  alias Lightning.Invocation

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    log_memory("DataclipLive.Show mount start")

    {:ok,
     socket
     |> assign(active_menu_item: :dataclip)}
  end

  @impl true
  def handle_params(%{"id" => id}, _url, socket) do
    log_memory("DataclipLive.Show handle_params start", socket: socket)

    # Get dataclip (should NOT load body due to load_in_query: false)
    dataclip = measure("load dataclip metadata", fn ->
      Invocation.get_dataclip!(id)
    end)

    socket =
      socket
      |> assign(:id, id)
      |> assign(:page_title, "Dataclip #{String.slice(id, 0..7)}")
      |> assign(:dataclip, dataclip)

    log_memory("DataclipLive.Show handle_params complete",
      socket: socket,
      assigns: [:dataclip])

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

      <div class="max-w-7xl mx-auto px-4 sm:px-6 lg:px-8 py-8">
        <!-- Metadata Section -->
        <div class="bg-white shadow rounded-lg mb-6">
          <div class="px-6 py-4 border-b border-gray-200">
            <h3 class="text-lg font-medium text-gray-900">Dataclip Details</h3>
          </div>
          <div class="px-6 py-4">
            <dl class="grid grid-cols-1 gap-x-4 gap-y-4 sm:grid-cols-2 lg:grid-cols-4">
              <div>
                <dt class="text-sm font-medium text-gray-500">ID</dt>
                <dd class="mt-1 text-sm text-gray-900 font-mono">{@dataclip.id}</dd>
              </div>
              <div>
                <dt class="text-sm font-medium text-gray-500">Type</dt>
                <dd class="mt-1">
                  <LightningWeb.Components.Common.dataclip_type_pill type={
                    @dataclip.type
                  } />
                </dd>
              </div>
              <div>
                <dt class="text-sm font-medium text-gray-500">Created</dt>
                <dd class="mt-1 text-sm text-gray-900">
                  <LightningWeb.Components.Common.datetime datetime={
                    @dataclip.inserted_at
                  } />
                </dd>
              </div>
              <div>
                <dt class="text-sm font-medium text-gray-500">Updated</dt>
                <dd class="mt-1 text-sm text-gray-900">
                  <LightningWeb.Components.Common.datetime datetime={
                    @dataclip.updated_at
                  } />
                </dd>
              </div>
              <%= if @dataclip.wiped_at do %>
                <div>
                  <dt class="text-sm font-medium text-gray-500">Wiped</dt>
                  <dd class="mt-1 text-sm text-gray-900">
                    <LightningWeb.Components.Common.datetime datetime={
                      @dataclip.wiped_at
                    } />
                  </dd>
                </div>
              <% end %>
            </dl>
          </div>
        </div>

    <!-- Body Section -->
        <div class="bg-white shadow rounded-lg">
          <div class="h-96 overflow-hidden">
            <%= if @dataclip.wiped_at do %>
              <div class="flex items-center justify-center h-full text-gray-500">
                <div class="text-center">
                  <div class="mx-auto h-12 w-12 text-gray-400">
                    <LightningWeb.Components.Icons.icon
                      name="hero-eye-slash"
                      class="h-12 w-12"
                    />
                  </div>
                  <h3 class="mt-2 text-sm font-semibold text-gray-900">
                    No Data Available
                  </h3>
                  <p class="mt-1 text-sm text-gray-500">
                    This dataclip's data has been wiped in accordance with the project's data retention policy.
                  </p>
                </div>
              </div>
            <% else %>
              <LightningWeb.Components.Viewers.dataclip_viewer
                dataclip={@dataclip}
                id={"dataclip-viewer-#{@dataclip.id}"}
              />
            <% end %>
          </div>
        </div>
      </div>
    </LayoutComponents.page_content>
    """
  end
end
