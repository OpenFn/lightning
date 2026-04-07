defmodule LightningWeb.RunLive.ChannelLogsComponent do
  @moduledoc false
  use LightningWeb, :live_component

  import Ecto.Changeset, only: [get_change: 2]

  alias Lightning.Channels
  alias Lightning.Channels.SearchParams
  alias LightningWeb.Components.Common
  alias LightningWeb.RunLive.Components, as: RunComponents

  alias Phoenix.LiveView.JS

  @impl true
  def update(assigns, socket) do
    params_changed? = assigns[:params] != socket.assigns[:params]

    socket = assign(socket, assigns)

    if params_changed? or not Map.has_key?(socket.assigns, :page) do
      %{project: project, params: params} = socket.assigns

      raw_filters = params["filters"] || %{}
      search_params = SearchParams.new(raw_filters)
      page_params = Map.take(params, ["page"])

      page =
        Channels.list_channel_requests(project, search_params, page_params)

      {:ok,
       socket
       |> assign_new(:channels, fn ->
         Channels.list_channels_for_project(project.id)
       end)
       |> assign(
         search_params: search_params,
         filters_changeset: SearchParams.changeset(raw_filters),
         page: page,
         pagination_path: &build_pagination_path(&1, project, search_params)
       )}
    else
      {:ok, socket}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%!-- Filters --%>
      <div class="top-0 self-start mb-4">
        <div class="flex flex-wrap items-center gap-2">
          <div class="relative">
            <% selected_channel =
              Enum.find(@channels, fn c ->
                get_change(@filters_changeset, :channel_id) == c.id
              end) %>
            <.filter_chip
              id="channel-filter-chip"
              active={selected_channel != nil}
              clear_fields={[{:channel_id, nil}]}
              target={@myself}
              phx-click={show_dropdown("channel_filter_dropdown")}
            >
              Channel is
              <%= if selected_channel do %>
                {selected_channel.name}
              <% else %>
                any
              <% end %>
            </.filter_chip>

            <div
              class="hidden absolute left-0 z-10 mt-2 w-60 origin-top-left rounded-md bg-white shadow-lg ring-1 ring-black/5 focus:outline-none"
              role="menu"
              id="channel_filter_dropdown"
              phx-click-away={hide_dropdown("channel_filter_dropdown")}
            >
              <div class="py-1" role="none">
                <a
                  href="#"
                  phx-click={
                    JS.push("apply_filters",
                      target: @myself,
                      value: %{filters: %{channel_id: nil}}
                    )
                    |> JS.hide(to: "#channel_filter_dropdown")
                  }
                  class={[
                    "block px-4 py-2 text-sm hover:bg-gray-100",
                    if(selected_channel == nil,
                      do: "bg-gray-100 text-gray-900",
                      else: "text-gray-700"
                    )
                  ]}
                  role="menuitem"
                >
                  All Channels
                </a>
                <%= for channel <- @channels do %>
                  <a
                    href="#"
                    phx-click={
                      JS.push("apply_filters",
                        target: @myself,
                        value: %{filters: %{channel_id: channel.id}}
                      )
                      |> JS.hide(to: "#channel_filter_dropdown")
                    }
                    class={[
                      "block px-4 py-2 text-sm hover:bg-gray-100",
                      if(selected_channel && selected_channel.id == channel.id,
                        do: "bg-gray-100 text-gray-900",
                        else: "text-gray-700"
                      )
                    ]}
                    role="menuitem"
                  >
                    {channel.name}
                  </a>
                <% end %>
              </div>
            </div>
          </div>
        </div>
      </div>

      <.table id="channel-requests-table" page={@page} url={@pagination_path}>
        <:header>
          <.tr>
            <.th>Request ID</.th>
            <.th>Request Path</.th>
            <.th>Channel Name</.th>
            <.th>Started At</.th>
            <.th>Status</.th>
            <.th>Error Message</.th>
          </.tr>
        </:header>
        <:body>
          <%= if Enum.empty?(@page.entries) do %>
            <.tr>
              <.td colspan={6}>
                <.empty_state
                  icon="hero-inbox"
                  message="No channel requests found."
                  interactive={false}
                />
              </.td>
            </.tr>
          <% else %>
            <%= for entry <- @page.entries do %>
              <.tr id={"request-#{entry.id}"}>
                <.td>
                  <span class="link-uuid" title={entry.request_id}>
                    {display_short_uuid(entry.request_id)}
                  </span>
                </.td>
                <.td class="text-sm text-gray-700">
                  {source_event_path(entry)}
                </.td>
                <.td class="text-sm text-gray-700">
                  <.link
                    navigate={
                      ~p"/projects/#{@project}/history/channels?#{%{filters: %{channel_id: entry.channel_id}}}"
                    }
                    class="text-indigo-600 hover:text-indigo-800"
                  >
                    {entry.channel.name}
                  </.link>
                </.td>
                <.td class="text-sm text-gray-500">
                  <Common.datetime datetime={entry.started_at} />
                </.td>
                <.td>
                  <RunComponents.channel_state_pill state={entry.state} />
                </.td>
                <.td class="text-sm text-gray-500 max-w-xs truncate">
                  {error_event_message(entry)}
                </.td>
              </.tr>
            <% end %>
          <% end %>
        </:body>
      </.table>
    </div>
    """
  end

  @impl true
  def handle_event("apply_filters", %{"filters" => filters}, socket) do
    filters = Map.reject(filters, fn {_, v} -> v == "" end)
    send(self(), {:channel_logs_filter, filters})
    {:noreply, socket}
  end

  defp source_event_path(channel_request),
    do: get_event_field(channel_request, :destination_response, :request_path)

  defp error_event_message(channel_request),
    do: get_event_field(channel_request, :error, :error_message)

  defp get_event_field(channel_request, event_type, field) do
    channel_request.channel_events
    |> Enum.find(&(&1.type == event_type))
    |> case do
      nil -> nil
      event -> Map.get(event, field)
    end
  end

  defp build_pagination_path(
         page_params,
         project,
         %SearchParams{channel_id: channel_id}
       ) do
    params =
      if channel_id,
        do: Keyword.put(page_params, :filters, %{channel_id: channel_id}),
        else: page_params

    ~p"/projects/#{project.id}/history/channels?#{params}"
  end
end
