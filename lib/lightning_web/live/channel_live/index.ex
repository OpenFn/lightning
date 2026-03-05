defmodule LightningWeb.ChannelLive.Index do
  @moduledoc false
  use LightningWeb, :live_view

  alias Lightning.Channels
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.ProjectUsers
  alias LightningWeb.ChannelLive.FormComponent
  alias LightningWeb.Components.Common

  import LightningWeb.ChannelLive.Helpers

  on_mount {LightningWeb.Hooks, :project_scope}
  on_mount {LightningWeb.Hooks, :check_limits}

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:banner>
        <Common.dynamic_component
          :if={assigns[:banner]}
          function={@banner.function}
          args={@banner.attrs}
        />
      </:banner>
      <:header>
        <LayoutComponents.header current_user={@current_user}>
          <:breadcrumbs>
            <LayoutComponents.breadcrumbs>
              <LayoutComponents.breadcrumb_project_picker label={@project.name} />
              <LayoutComponents.breadcrumb>
                <:label>{@page_title}</:label>
              </LayoutComponents.breadcrumb>
            </LayoutComponents.breadcrumbs>
          </:breadcrumbs>
        </LayoutComponents.header>
      </:header>
      <LayoutComponents.centered>
        <.channel_metrics channel_stats={@channel_stats} project={@project} />
        <div class="w-full">
          <div class="mt-14 flex justify-between mb-3">
            <h3 class="text-3xl font-bold">
              Channels
              <span class="text-base font-normal">({length(@channels)})</span>
            </h3>
            <.link
              :if={@can_create_channel}
              patch={~p"/projects/#{@project}/channels/new"}
            >
              <.button id="new-channel-button" theme="primary">
                New Channel
              </.button>
            </.link>
            <.button
              :if={!@can_create_channel}
              id="new-channel-button"
              theme="primary"
              disabled
              tooltip="You are not authorized to perform this action."
            >
              New Channel
            </.button>
          </div>
          <.channels_table
            id="channels-table"
            channels={@channels}
            can_edit_channel={@can_edit_channel}
            can_delete_channel={@can_delete_channel}
            project={@project}
          />
        </div>
      </LayoutComponents.centered>
    </LayoutComponents.page_content>
    <.live_component
      :if={@live_action in [:new, :edit]}
      module={FormComponent}
      id={
        (@selected_channel && @selected_channel.id &&
           "edit-channel-#{@selected_channel.id}") || :new
      }
      action={@live_action}
      channel={@selected_channel}
      project={@project}
      current_user={@current_user}
      on_close={JS.patch(~p"/projects/#{@project}/channels")}
    />
    """
  end

  @impl true
  def mount(_params, _session, socket) do
    %{current_user: current_user, project: project} = socket.assigns

    can_create_channel =
      ProjectUsers
      |> Permissions.can?(:create_channel, current_user, project)

    can_edit_channel =
      ProjectUsers
      |> Permissions.can?(:update_channel, current_user, project)

    can_delete_channel =
      ProjectUsers
      |> Permissions.can?(:delete_channel, current_user, project)

    {:ok,
     socket
     |> assign(
       active_menu_item: :channels,
       can_create_channel: can_create_channel,
       can_edit_channel: can_edit_channel,
       can_delete_channel: can_delete_channel,
       channels: [],
       channel_stats: %{total_channels: 0, total_requests: 0}
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    project_id = socket.assigns.project.id

    socket
    |> assign(
      page_title: "Channels",
      channels: Channels.list_channels_for_project_with_stats(project_id),
      channel_stats: Channels.get_channel_stats_for_project(project_id),
      selected_channel: nil
    )
  end

  defp apply_action(socket, :new, _params) do
    if socket.assigns.can_create_channel do
      socket
      |> assign(
        page_title: "New Channel",
        selected_channel: %Lightning.Channels.Channel{channel_auth_methods: []}
      )
    else
      socket
      |> put_flash(:error, "You are not authorized to create channels.")
      |> push_navigate(to: ~p"/projects/#{socket.assigns.project.id}/channels")
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    if socket.assigns.can_edit_channel do
      channel = Channels.get_channel!(id, include: [:channel_auth_methods])

      socket
      |> assign(
        page_title: "Edit Channel",
        selected_channel: channel
      )
    else
      socket
      |> put_flash(:error, "You are not authorized to edit channels.")
      |> push_navigate(to: ~p"/projects/#{socket.assigns.project.id}/channels")
    end
  end

  @impl true
  def handle_event(
        "toggle_channel_state",
        %{"channel_state" => enabled?, "value_key" => channel_id},
        socket
      ) do
    with :ok <- check_can_edit_channel(socket),
         {:ok, channel} <- fetch_project_channel(socket, channel_id) do
      case Channels.update_channel(channel, %{enabled: enabled?},
             actor: socket.assigns.current_user
           ) do
        {:ok, _channel} ->
          socket
          |> put_flash(:info, "Channel updated")
          |> push_patch(to: ~p"/projects/#{socket.assigns.project.id}/channels")
          |> noreply()

        {:error, _changeset} ->
          socket
          |> put_flash(:error, "Failed to update channel. Please try again.")
          |> noreply()
      end
    end
  end

  @impl true
  def handle_event("delete_channel", %{"id" => id}, socket) do
    with :ok <- check_can_delete_channel(socket),
         {:ok, channel} <- fetch_project_channel(socket, id) do
      case Channels.delete_channel(channel, actor: socket.assigns.current_user) do
        {:ok, _} ->
          socket
          |> put_flash(:info, "Channel deleted.")
          |> push_patch(to: ~p"/projects/#{socket.assigns.project.id}/channels")
          |> noreply()

        {:error, changeset} ->
          message =
            if Keyword.has_key?(changeset.errors, :channel_snapshots),
              do:
                "Cannot delete \"#{channel.name}\" — it has request history that must be retained.",
              else: "Failed to delete channel. Please try again."

          socket |> put_flash(:error, message) |> noreply()
      end
    end
  end

  defp check_can_edit_channel(socket) do
    if socket.assigns.can_edit_channel do
      :ok
    else
      socket
      |> put_flash(:error, "You are not authorized to perform this action.")
      |> noreply()
    end
  end

  defp check_can_delete_channel(socket) do
    if socket.assigns.can_delete_channel do
      :ok
    else
      socket
      |> put_flash(:error, "You are not authorized to perform this action.")
      |> noreply()
    end
  end

  defp fetch_project_channel(socket, channel_id) do
    case Channels.get_channel_for_project(socket.assigns.project.id, channel_id) do
      %{} = channel -> {:ok, channel}
      nil -> socket |> put_flash(:error, "Channel not found.") |> noreply()
    end
  end

  # --- Private components ---

  attr :channel_stats, :map, required: true
  attr :project, :map, required: true

  defp channel_metrics(assigns) do
    ~H"""
    <div class="grid gap-6 grid-cols-2 mb-8">
      <div class="bg-white shadow rounded-lg py-2 px-6">
        <h2 class="text-sm text-gray-500">Total Channels</h2>
        <div class="text-3xl font-bold text-gray-800">
          {@channel_stats.total_channels}
        </div>
      </div>
      <div class="bg-white shadow rounded-lg py-2 px-6">
        <div class="flex items-center justify-between">
          <h2 class="text-sm text-gray-500">Total Requests</h2>
          <.link
            navigate={~p"/projects/#{@project}/history/channels"}
            class="text-xs text-indigo-600 hover:text-indigo-800"
          >
            View all
          </.link>
        </div>
        <div class="text-3xl font-bold text-gray-800">
          {@channel_stats.total_requests}
        </div>
      </div>
    </div>
    """
  end

  attr :id, :string, required: true
  attr :channels, :list, required: true
  attr :project, :map, required: true
  attr :can_edit_channel, :boolean, default: false
  attr :can_delete_channel, :boolean, default: false

  defp channels_table(%{channels: []} = assigns) do
    ~H"""
    <div class="text-center py-8">
      <p class="text-gray-500">No channels found.</p>
    </div>
    """
  end

  defp channels_table(assigns) do
    ~H"""
    <.table id={@id}>
      <:header>
        <.tr>
          <.th>Name</.th>
          <.th>Destination</.th>
          <.th>Requests</.th>
          <.th>Last Activity</.th>
          <.th>Enabled</.th>
          <.th><span class="sr-only">Actions</span></.th>
        </.tr>
      </:header>
      <:body>
        <%= for %{channel: channel, request_count: count, last_activity: last_at} <-
              @channels do %>
          <.tr id={"channel-#{channel.id}"}>
            <.td class="wrap-break-word max-w-[15rem]">
              <span class={[
                "font-medium",
                if(channel.enabled,
                  do: "text-gray-900",
                  else: "text-gray-400"
                )
              ]}>
                {channel.name}
              </span>
            </.td>
            <.td>
              <div class="flex items-center gap-1.5 font-mono text-sm leading-none text-gray-600">
                <.icon
                  name="lucide-square-arrow-right-exit"
                  class="h-4 w-4 shrink-0 text-gray-400"
                />
                <span class="wrap-break-word max-w-[20rem] translate-y-px">
                  {channel.sink_url}
                </span>
              </div>
              <Common.wrapper_tooltip
                id={"copy-url-tip-#{channel.id}"}
                tooltip="Copy proxy URL"
              >
                <.proxy_url_copy
                  id={"copy-url-btn-#{channel.id}"}
                  channel_id={channel.id}
                  class="mt-1 hover:text-gray-600"
                  text_class="text-gray-400 max-w-[16rem] group-hover/copy:text-gray-600"
                >
                  <:leading>
                    <.icon
                      name="lucide-circle-dot"
                      class="h-4 w-4 shrink-0 text-gray-300"
                    />
                  </:leading>
                  <:trailing>
                    <.icon
                      name="hero-clipboard-document"
                      class="h-4 w-4 shrink-0 text-gray-300 opacity-0 group-hover/copy:opacity-100 transition-opacity"
                    />
                  </:trailing>
                </.proxy_url_copy>
              </Common.wrapper_tooltip>
            </.td>
            <.td class="text-gray-700">
              <.link
                navigate={
                  ~p"/projects/#{@project}/history/channels?#{%{filters: %{channel_id: channel.id}}}"
                }
                class="text-indigo-600 hover:text-indigo-800"
              >
                {count}
              </.link>
            </.td>
            <.td class="text-gray-500 text-sm">
              <.link
                navigate={
                  ~p"/projects/#{@project}/history/channels?#{%{filters: %{channel_id: channel.id}}}"
                }
                class="hover:text-gray-700"
              >
                <%= if last_at do %>
                  <Common.datetime datetime={last_at} />
                <% else %>
                  <span class="italic">Never</span>
                <% end %>
              </.link>
            </.td>
            <.td>
              <%= if @can_edit_channel do %>
                <.input
                  id={channel.id}
                  type="toggle"
                  name="channel_state"
                  value={channel.enabled}
                  tooltip={unless channel.enabled, do: "#{channel.name} (disabled)"}
                  on_click="toggle_channel_state"
                  value_key={channel.id}
                />
              <% else %>
                <span class={[
                  "text-sm",
                  if(channel.enabled, do: "text-gray-700", else: "text-gray-400")
                ]}>
                  {if channel.enabled, do: "Enabled", else: "Disabled"}
                </span>
              <% end %>
            </.td>
            <.td class="text-right">
              <div class="flex items-center justify-end gap-2">
                <.link
                  :if={@can_edit_channel}
                  patch={~p"/projects/#{@project}/channels/#{channel.id}/edit"}
                >
                  <.button theme="secondary" size="sm">Edit</.button>
                </.link>
                <.button
                  :if={@can_delete_channel}
                  theme="danger"
                  size="sm"
                  phx-click="delete_channel"
                  phx-value-id={channel.id}
                  data-confirm={"Delete \"#{channel.name}\"? This cannot be undone."}
                >
                  Delete
                </.button>
              </div>
            </.td>
          </.tr>
        <% end %>
      </:body>
    </.table>
    """
  end
end
