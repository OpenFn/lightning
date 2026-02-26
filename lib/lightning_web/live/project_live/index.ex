defmodule LightningWeb.ProjectLive.Index do
  @moduledoc """
  LiveView for listing and managing Projects
  """
  use LightningWeb, :live_view

  alias Lightning.Accounts
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Users
  alias Lightning.Projects
  alias LightningWeb.Live.Helpers.TableHelpers

  @default_sort "name"
  @allowed_sorts ~w(name inserted_at description owner scheduled_deletion)
  @default_page_size 10
  @max_page_size 100

  @impl true
  def mount(_params, _session, socket) do
    can_access_admin_space =
      Users
      |> Permissions.can?(:access_admin_space, socket.assigns.current_user, {})

    if can_access_admin_space do
      {:ok, socket, layout: {LightningWeb.Layouts, :settings}}
    else
      {:ok,
       put_flash(socket, :nav, :no_access)
       |> push_navigate(to: "/projects")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    socket =
      socket
      |> assign(:table_params, normalize_table_params(params))
      |> apply_action(socket.assigns.live_action, params)

    {:noreply, socket}
  end

  defp apply_action(socket, :index, _params) do
    table_params = socket.assigns.table_params
    page = Projects.list_projects_for_admin(table_params)

    socket
    |> assign(
      page_title: "Projects",
      active_menu_item: :projects,
      page: page,
      pagination_path: pagination_path(socket, table_params),
      sort_key: table_params["sort"],
      sort_direction: table_params["dir"],
      filter: table_params["filter"]
    )
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(
      page_title: "Edit Project",
      active_menu_item: :projects,
      project: Projects.get_project_with_users!(id),
      users: Accounts.list_users(),
      sort_key: "name",
      sort_direction: "asc",
      filter: ""
    )
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(
      page_title: "New Project",
      active_menu_item: :projects,
      project: %Lightning.Projects.Project{project_users: []},
      users: Accounts.list_users(),
      sort_key: "name",
      sort_direction: "asc",
      filter: ""
    )
  end

  defp apply_action(socket, :delete, %{"id" => id}) do
    table_params = socket.assigns.table_params
    page = Projects.list_projects_for_admin(table_params)

    socket
    |> assign(
      page_title: "Projects",
      active_menu_item: :projects,
      page: page,
      pagination_path: pagination_path(socket, table_params),
      project: Projects.get_project(id),
      sort_key: table_params["sort"],
      sort_direction: table_params["dir"],
      filter: table_params["filter"]
    )
  end

  @impl true
  def handle_event(
        "cancel_deletion",
        %{"id" => project_id},
        socket
      ) do
    Projects.cancel_scheduled_deletion(project_id)

    {:noreply,
     socket
     |> put_flash(:info, "Project deletion canceled")
     |> push_patch(
       to: Routes.project_index_path(socket, :index, socket.assigns.table_params)
     )}
  end

  def handle_event("sort", %{"by" => sort_key}, socket) do
    {sort_key, sort_direction} =
      TableHelpers.toggle_sort_direction(
        socket.assigns.sort_direction,
        socket.assigns.sort_key,
        sort_key
      )

    params =
      socket.assigns.table_params
      |> Map.put("sort", sort_key)
      |> Map.put("dir", sort_direction)
      |> Map.put("page", "1")

    {:noreply,
     push_patch(socket, to: Routes.project_index_path(socket, :index, params))}
  end

  def handle_event("filter", %{"value" => filter}, socket) do
    params =
      socket.assigns.table_params
      |> Map.put("filter", String.trim(filter))
      |> Map.put("page", "1")

    {:noreply,
     push_patch(socket, to: Routes.project_index_path(socket, :index, params))}
  end

  def handle_event("clear_filter", _params, socket) do
    params =
      socket.assigns.table_params
      |> Map.put("filter", "")
      |> Map.put("page", "1")

    {:noreply,
     push_patch(socket, to: Routes.project_index_path(socket, :index, params))}
  end

  def delete_action(assigns) do
    ~H"""
    <%= if @project.scheduled_deletion do %>
      <.link
        id={"cancel-deletion-#{@project.id}"}
        href="#"
        phx-click="cancel_deletion"
        phx-value-id={@project.id}
      >
        Cancel deletion
      </.link>

      <.link
        id={"delete-now-#{@project.id}"}
        navigate={~p"/settings/projects/#{@project.id}/delete"}
      >
        Delete now
      </.link>
    <% else %>
      <.link
        id={"delete-#{@project.id}"}
        navigate={Routes.project_index_path(@socket, :delete, @project)}
      >
        Delete
      </.link>
    <% end %>
    """
  end

  defp normalize_table_params(params) do
    params = Map.new(params, fn {k, v} -> {to_string(k), v} end)

    %{
      "filter" => normalize_filter(Map.get(params, "filter")),
      "sort" => normalize_sort(Map.get(params, "sort")),
      "dir" => normalize_dir(Map.get(params, "dir")),
      "page" => Map.get(params, "page") |> parse_positive_int(1) |> Integer.to_string(),
      "page_size" =>
        Map.get(params, "page_size")
        |> parse_positive_int(@default_page_size)
        |> min(@max_page_size)
        |> Integer.to_string()
    }
  end

  defp normalize_sort(sort) when is_binary(sort) do
    if sort in @allowed_sorts, do: sort, else: @default_sort
  end

  defp normalize_sort(sort) when is_atom(sort) do
    sort
    |> Atom.to_string()
    |> normalize_sort()
  end

  defp normalize_sort(_), do: @default_sort

  defp normalize_dir(dir) when dir in ["asc", :asc], do: "asc"
  defp normalize_dir(dir) when dir in ["desc", :desc], do: "desc"
  defp normalize_dir(_), do: "asc"

  defp normalize_filter(nil), do: ""

  defp normalize_filter(filter) do
    filter
    |> to_string()
    |> String.trim()
  end

  defp parse_positive_int(value, _default) when is_integer(value) and value > 0,
    do: value

  defp parse_positive_int(value, default) do
    case Integer.parse(to_string(value || "")) do
      {int, ""} when int > 0 -> int
      _ -> default
    end
  end

  defp pagination_path(socket, table_params) do
    fn route_params ->
      params =
        route_params
        |> Enum.into(%{})
        |> Map.merge(Map.take(table_params, ["filter", "sort", "dir", "page_size"]))
        |> Enum.reject(fn {_key, value} -> value in [nil, ""] end)
        |> Map.new()

      Routes.project_index_path(socket, :index, params)
    end
  end

  def get_project_owner_name(project) do
    case Enum.find(project.project_users, fn pu -> pu.role == :owner end) do
      %{user: user} when not is_nil(user) ->
        String.trim("#{user.first_name} #{user.last_name}")

      _ ->
        ""
    end
  end
end
