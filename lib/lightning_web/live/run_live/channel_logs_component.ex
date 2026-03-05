defmodule LightningWeb.RunLive.ChannelLogsComponent do
  @moduledoc false
  use LightningWeb, :live_component

  alias Lightning.Channels
  alias Lightning.Channels.SearchParams
  alias LightningWeb.Components.Common
  alias LightningWeb.RunLive.Components, as: RunComponents

  @impl true
  def update(assigns, socket) do
    %{project: project, params: params} = assigns

    socket = assign(socket, assigns)

    channels = Channels.list_channels_for_project(project.id)
    raw_filters = params["filters"] || %{}
    search_params = SearchParams.new(raw_filters)
    page_params = Map.take(params, ["page"])

    page =
      Channels.list_channel_requests(project, search_params, page_params)

    {:ok,
     socket
     |> assign(
       channels: channels,
       search_params: search_params,
       filters_changeset: SearchParams.changeset(raw_filters),
       page: page,
       pagination_path: &build_pagination_path(&1, project, search_params)
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <%!-- Filters --%>
      <div class="top-0 self-start mb-2">
        <.form
          :let={f}
          for={@filters_changeset}
          as={:filters}
          id="channel-request-filter-form"
          phx-change="apply_filters"
          phx-target={@myself}
        >
          <div class="flex gap-2">
            <div>
              <div class="font-medium mt-4 mb-2 text-gray-500 text-sm">
                Channel
              </div>
              <.input
                type="select"
                field={f[:channel_id]}
                prompt="All Channels"
                options={Enum.map(@channels, fn c -> {c.name, c.id} end)}
                class="w-60"
              />
            </div>
          </div>
        </.form>
      </div>

      <div class="mt-2">
        <div class="flex justify-between items-end">
          <div class="text-md text-gray-500 font-medium truncate w-full">
            Channel Requests
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
                  <RunComponents.state_pill state={entry.state} />
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

  defp source_event_path(channel_request) do
    channel_request.channel_events
    |> Enum.find(&(&1.type == :sink_response))
    |> case do
      nil -> nil
      event -> event.request_path
    end
  end

  defp error_event_message(channel_request) do
    channel_request.channel_events
    |> Enum.find(&(&1.type == :error))
    |> case do
      nil -> nil
      event -> event.error_message
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
