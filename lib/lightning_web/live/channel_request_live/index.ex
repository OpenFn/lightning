defmodule LightningWeb.ChannelRequestLive.Index do
  @moduledoc false
  use LightningWeb, :live_view

  import PetalComponents.Badge

  alias Lightning.Channels
  alias Lightning.Channels.SearchParams
  alias LightningWeb.Components.Common

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    %{project: project} = socket.assigns
    channels = Channels.list_channels_for_project(project.id)

    {:ok,
     socket
     |> assign(
       active_menu_item: :channel_requests,
       channels: channels,
       search_params: SearchParams.new(%{}),
       filters_changeset: SearchParams.changeset(),
       page: empty_page()
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    %{project: project} = socket.assigns
    raw_filters = params["filters"] || %{}
    search_params = SearchParams.new(raw_filters)
    page_params = Map.take(params, ["page"])

    page = Channels.list_channel_requests(project, search_params, page_params)

    {:noreply,
     socket
     |> assign(
       page_title: "Channel Requests",
       search_params: search_params,
       filters_changeset: SearchParams.changeset(raw_filters),
       page: page,
       pagination_path: &build_pagination_path(&1, project, search_params)
     )}
  end

  @impl true
  def handle_event("apply_filters", %{"filters" => filters}, socket) do
    %{project: project} = socket.assigns
    filters = Map.reject(filters, fn {_, v} -> v == "" end)

    {:noreply,
     push_patch(socket,
       to: ~p"/projects/#{project.id}/channels/requests?#{%{filters: filters}}"
     )}
  end

  # Helpers for extracting fields from preloaded channel_events

  defp source_event_path(channel_request) do
    channel_request.channel_events
    |> Enum.find(&(&1.type == :source_received))
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

  defp state_color(:success), do: "success"
  defp state_color(:pending), do: "warning"
  defp state_color(:failed), do: "danger"
  defp state_color(:timeout), do: "warning"
  defp state_color(:error), do: "danger"

  defp build_pagination_path(
         page_params,
         project,
         %SearchParams{channel_id: nil}
       ) do
    ~p"/projects/#{project.id}/channels/requests?#{page_params}"
  end

  defp build_pagination_path(
         page_params,
         project,
         %SearchParams{channel_id: channel_id}
       ) do
    ~p"/projects/#{project.id}/channels/requests?#{%{filters: %{channel_id: channel_id}, page: page_params}}"
  end

  defp empty_page do
    %{
      entries: [],
      page_number: 1,
      page_size: 10,
      total_entries: 0,
      total_pages: 0
    }
  end
end
