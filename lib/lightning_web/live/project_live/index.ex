defmodule LightningWeb.ProjectLive.Index do
  @moduledoc """
  LiveView for listing and managing Projects
  """
  use LightningWeb, :live_view

  alias Lightning.Policies.Users
  alias Lightning.Policies.Permissions
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
      page_title: "Projects",
      active_menu_item: :projects,
      projects: Projects.list_projects()
    )
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(
      page_title: "Edit Project",
      active_menu_item: :projects,
      project: Projects.get_project_with_users!(id),
      users: Lightning.Accounts.list_users()
    )
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(
      page_title: "New Project",
      active_menu_item: :projects,
      project: %Lightning.Projects.Project{project_users: []},
      users: Lightning.Accounts.list_users()
    )
  end

  defp apply_action(socket, :delete, %{"id" => id}) do
    socket
    |> assign(
      page_title: "Projects",
      active_menu_item: :settings,
      projects: Projects.list_projects(),
      project: Projects.get_project(id)
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

  def delete_action(assigns) do
    if assigns.project.scheduled_deletion do
      ~H"""
      <span>
        <.link
          id={"cancel-deletion-#{@project.id}"}
          href="#"
          phx-click="cancel_deletion"
          phx-value-id={@project.id}
        >
          Cancel deletion
        </.link>
      </span>
      |
      <span>
        <.link
          id={"delete-now-#{@project.id}"}
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
          navigate={Routes.project_index_path(@socket, :delete, @project)}
        >
          Delete
        </.link>
      </span>
      """
    end
  end
end
