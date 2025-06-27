defmodule LightningWeb.ProjectLive.Index do
  @moduledoc """
  LiveView for listing and managing Projects
  """
  use LightningWeb, :live_view

  import Ecto.Query
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Users
  alias Lightning.Projects

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
      case socket.assigns do
        %{sort_key: ^sort_key, sort_direction: "asc"} ->
          {sort_key, "desc"}

        %{sort_key: ^sort_key, sort_direction: "desc"} ->
          {sort_key, "asc"}

        _ ->
          {sort_key, "asc"}
      end

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
    if assigns.project.scheduled_deletion do
      ~H"""
      <span>
        <.link
          id={"cancel-deletion-#{@project.id}"}
          href="#"
          class="table-action"
          phx-click="cancel_deletion"
          phx-value-id={@project.id}
        >
          Cancel deletion
        </.link>
      </span>
      <span>
        <.link
          id={"delete-now-#{@project.id}"}
          class="table-action"
          navigate={~p"/settings/projects/#{@project.id}/delete"}
        >
          Delete now
        </.link>
      </span>
      """
    else
      ~H"""
      <span>
        <.link
          id={"delete-#{@project.id}"}
          class="table-action"
          navigate={Routes.project_index_path(@socket, :delete, @project)}
        >
          Delete
        </.link>
      </span>
      """
    end
  end

  defp list_projects(filter, sort_key, sort_direction) do
    projects = list_projects_with_owners()

    projects
    |> filter_projects(filter)
    |> sort_projects(sort_key, sort_direction)
  end

  defp list_projects_with_owners do
    from(p in Lightning.Projects.Project,
      preload: [project_users: :user],
      order_by: p.name
    )
    |> Lightning.Repo.all()
  end

  defp filter_projects(projects, "") do
    projects
  end

  defp filter_projects(projects, filter) do
    filter_lower = String.downcase(filter)

    Enum.filter(projects, fn project ->
      owner_name = get_project_owner_name(project)

      String.contains?(String.downcase(project.name || ""), filter_lower) ||
        String.contains?(
          String.downcase(project.description || ""),
          filter_lower
        ) ||
        String.contains?(String.downcase(owner_name), filter_lower)
    end)
  end

  defp sort_projects(projects, sort_key, sort_direction) do
    compare_fn =
      case sort_direction do
        "asc" -> &<=/2
        "desc" -> &>=/2
      end

    Enum.sort_by(
      projects,
      fn project ->
        case sort_key do
          "name" ->
            project.name || ""

          "inserted_at" ->
            project.inserted_at

          "description" ->
            project.description || ""

          "owner" ->
            get_project_owner_name(project)

          "scheduled_deletion" ->
            project.scheduled_deletion || ~U[9999-12-31 23:59:59Z]

          _ ->
            project.name || ""
        end
      end,
      compare_fn
    )
  end

  defp get_project_owner_name(project) do
    case Enum.find(project.project_users, fn pu -> pu.role == :owner end) do
      %{user: user} when not is_nil(user) ->
        "#{user.first_name || ""} #{user.last_name || ""}" |> String.trim()

      _ ->
        ""
    end
  end
end
