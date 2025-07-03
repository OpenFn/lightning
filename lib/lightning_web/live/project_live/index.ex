defmodule LightningWeb.ProjectLive.Index do
  @moduledoc """
  LiveView for listing and managing Projects
  """
  use LightningWeb, :live_view

  import Ecto.Query
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Users
  alias Lightning.Projects
  alias LightningWeb.Live.Helpers.TableHelpers

  # Configuration for project table sorting
  defp project_sort_map do
    %{
      "name" => fn project -> project.name || "" end,
      "inserted_at" => :inserted_at,
      "description" => fn project -> project.description || "" end,
      "owner" => fn project -> get_project_owner_name(project) end,
      "scheduled_deletion" => fn project ->
        project.scheduled_deletion || ~U[9999-12-31 23:59:59Z]
      end
    }
  end

  defp project_search_fields do
    [
      fn project -> project.name || "" end,
      fn project -> project.description || "" end,
      fn project -> get_project_owner_name(project) end
    ]
  end

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
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(
      page_title: "Projects",
      active_menu_item: :projects,
      projects: list_projects("", "name", "asc"),
      sort_key: "name",
      sort_direction: "asc",
      filter: ""
    )
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(
      page_title: "Edit Project",
      active_menu_item: :projects,
      project: Projects.get_project_with_users!(id),
      users: Lightning.Accounts.list_users(),
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
      users: Lightning.Accounts.list_users(),
      sort_key: "name",
      sort_direction: "asc",
      filter: ""
    )
  end

  defp apply_action(socket, :delete, %{"id" => id}) do
    socket
    |> assign(
      page_title: "Projects",
      active_menu_item: :settings,
      projects: list_projects("", "name", "asc"),
      project: Projects.get_project(id),
      sort_key: "name",
      sort_direction: "asc",
      filter: ""
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
     |> push_patch(to: ~p"/settings/projects")}
  end

  def handle_event("sort", %{"by" => sort_key}, socket) do
    {sort_key, sort_direction} =
      TableHelpers.toggle_sort_direction(
        socket.assigns.sort_direction,
        socket.assigns.sort_key,
        sort_key
      )

    projects = list_projects(socket.assigns.filter, sort_key, sort_direction)

    {:noreply,
     assign(socket,
       projects: projects,
       sort_key: sort_key,
       sort_direction: sort_direction
     )}
  end

  def handle_event("filter", %{"value" => filter}, socket) do
    projects =
      list_projects(
        filter,
        socket.assigns.sort_key,
        socket.assigns.sort_direction
      )

    {:noreply,
     assign(socket,
       projects: projects,
       filter: filter
     )}
  end

  def handle_event("clear_filter", _params, socket) do
    projects =
      list_projects("", socket.assigns.sort_key, socket.assigns.sort_direction)

    {:noreply,
     assign(socket,
       projects: projects,
       filter: ""
     )}
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

  defp list_projects(filter, sort_key, sort_direction) do
    projects = list_projects_with_owners()

    TableHelpers.filter_and_sort(
      projects,
      filter,
      project_search_fields(),
      sort_key,
      sort_direction,
      project_sort_map()
    )
  end

  defp list_projects_with_owners do
    from(p in Lightning.Projects.Project,
      preload: [project_users: :user],
      order_by: p.name
    )
    |> Lightning.Repo.all()
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
