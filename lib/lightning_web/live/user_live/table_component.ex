defmodule LightningWeb.UserLive.TableComponent do
  @moduledoc false

  use LightningWeb, :live_component
  import LightningWeb.UserLive.Components

  alias Lightning.Accounts
  alias Lightning.Accounts.AdminSearchParams
  alias LightningWeb.Live.Helpers.TableHelpers

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.users_table
        socket={@socket}
        target={@myself}
        live_action={@live_action}
        delete_user={assigns[:delete_user]}
        page={@page}
        pagination_path={@pagination_path}
        sort_key={@sort_key}
        sort_direction={@sort_direction}
        filter={@filter}
        user_deletion_modal={@user_deletion_modal}
      />
    </div>
    """
  end

  @impl true
  def mount(socket) do
    table_params = AdminSearchParams.default_uri_params()

    {:ok,
     socket
     |> assign(:table_params, table_params)
     |> assign_table_state(table_params, empty_page())}
  end

  @impl true
  def update(assigns, socket) do
    table_params = Map.get(assigns, :table_params, socket.assigns.table_params)
    search_params = AdminSearchParams.new(table_params)
    page = Accounts.list_all_users(search_params)

    {:ok,
     socket
     |> assign(assigns)
     |> assign_table_state(AdminSearchParams.to_uri_params(search_params), page)}
  end

  @impl true
  def handle_event("sort", %{"by" => sort_key}, socket) do
    {sort_key, sort_direction} =
      TableHelpers.toggle_sort_direction(
        socket.assigns.sort_direction,
        socket.assigns.sort_key,
        sort_key
      )

    params =
      socket.assigns.table_params
      |> Map.put("sort_by", sort_key)
      |> Map.put("sort_direction", sort_direction)
      |> Map.put("page", "1")

    {:noreply,
     push_patch(socket, to: Routes.user_index_path(socket, :index, params))}
  end

  def handle_event("filter", %{"value" => filter}, socket) do
    params =
      socket.assigns.table_params
      |> Map.put("search_term", String.trim(filter))
      |> Map.put("page", "1")

    {:noreply,
     push_patch(socket, to: Routes.user_index_path(socket, :index, params))}
  end

  def handle_event("clear_filter", _params, socket) do
    params =
      socket.assigns.table_params
      |> Map.put("search_term", "")
      |> Map.put("page", "1")

    {:noreply,
     push_patch(socket, to: Routes.user_index_path(socket, :index, params))}
  end

  defp assign_table_state(socket, table_params, page) do
    assign(socket,
      page: page,
      filter: table_params["search_term"],
      sort_key: table_params["sort_by"],
      sort_direction: table_params["sort_direction"],
      table_params: table_params,
      pagination_path: pagination_path(socket, table_params)
    )
  end

  defp empty_page do
    params = AdminSearchParams.new()

    %Scrivener.Page{
      entries: [],
      page_number: 1,
      page_size: params.page_size,
      total_entries: 0,
      total_pages: 1
    }
  end

  defp pagination_path(socket, table_params) do
    fn route_params ->
      params =
        route_params
        |> Enum.into(%{})
        |> Map.merge(
          Map.take(table_params, [
            "search_term",
            "sort_by",
            "sort_direction",
            "page_size"
          ])
        )
        |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
        |> Map.new()

      Routes.user_index_path(socket, :index, params)
    end
  end
end
