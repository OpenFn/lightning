defmodule LightningWeb.ProjectLive.Index do
  @moduledoc """
  LiveView for listing and managing Projects
  """
  use LightningWeb, :live_view

  alias Lightning.Policies.{Users, ProjectUsers, Permissions}
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
       put_flash(socket, :error, "You can't access that page")
       |> push_redirect(to: "/")}
    end
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(
      active_menu_item: :projects,
      projects: Projects.list_projects(),
      page_title: "Projects"
    )
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "New Project")
    |> assign(active_menu_item: :settings)
    |> assign(:project, Projects.get_project_with_users!(id))
    |> assign(:users, Lightning.Accounts.list_users())
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Project")
    |> assign(active_menu_item: :settings)
    |> assign(:project, %Lightning.Projects.Project{})
    |> assign(:users, Lightning.Accounts.list_users())
  end

  @impl true
  def handle_event(
        "delete_now",
        %{"id" => project_id},
        socket
      ) do
    project = Projects.get_project(project_id)

    if can_delete_project(socket.assigns.current_user, project) do
      Projects.delete_project(project)
      |> case do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(
             active_menu_item: :projects,
             projects: Projects.list_projects(),
             page_title: "Projects"
           )
           |> put_flash(:info, "Project deleted successfully")
           |> push_patch(to: ~p"/settings/projects")}

        {:error, changeset} ->
          {:noreply,
           socket
           |> assign(changeset: changeset)
           |> put_flash(:error, "Can't delete project")}
      end
    else
      put_flash(socket, :error, "You can't perform this action")
      |> push_patch(to: ~p"/profile/projects")
    end
  end

  def handle_event(
        "cancel_delete",
        %{"id" => project_id},
        socket
      ) do
    project = Projects.get_project(project_id)

    case Projects.cancel_scheduled_deletion(project) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Canceled project deletion schedule")
         |> push_patch(to: ~p"/settings/projects")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :scheduled_deletion_changeset, changeset)}
    end
  end

  def handle_event(
        "schedule_delete",
        %{"id" => project_id},
        socket
      ) do
    project = Projects.get_project(project_id)

    case Projects.schedule_project_deletion(project) do
      {:ok, _project} ->
        {:noreply,
         socket
         |> put_flash(:info, "Project scheduled for deletion")
         |> push_patch(to: ~p"/settings/projects")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :scheduled_deletion_changeset, changeset)}
    end
  end

  # TODO: this results in n+1 queries, we need to precalculate the permissions
  # and have zipped list of projects and the permissions so when we iterate
  # over them in the templace we don't generate n number of queries
  def can_request_delete_project(current_user, project),
    do:
      ProjectUsers
      |> Permissions.can?(:request_delete_project, current_user, project)

  def can_delete_project(current_user, project),
    do: Users |> Permissions.can?(:delete_project, current_user, project)

  def request_project_deletion(current_user, project) do
    is_nil(project.scheduled_deletion) and
      (can_request_delete_project(current_user, project) or
         current_user.role == :superuser)
  end
end
