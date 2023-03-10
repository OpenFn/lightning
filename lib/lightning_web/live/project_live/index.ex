defmodule LightningWeb.ProjectLive.Index do
  @moduledoc """
  LiveView for listing and managing Projects
  """
  use LightningWeb, :live_view

  alias Lightning.Policies.{Users, Permissions}
  alias Lightning.Projects

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket, layout: {LightningWeb.LayoutView, :settings}}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    can_view_projects =
      Users
      |> Permissions.can(:view_projects, socket.assigns.current_user)

    if can_view_projects do
      socket
      |> assign(
        active_menu_item: :projects,
        can_view_projects: can_view_projects,
        projects: Projects.list_projects(),
        page_title: "Projects"
      )
    else
      put_flash(socket, :error, "You can't access that page")
      |> push_redirect(to: "/")
    end
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    can_edit_projects =
      Users |> Permissions.can(:edit_projects, socket.assigns.current_user, {})

    if can_edit_projects do
      socket
      |> assign(:page_title, "New Project")
      |> assign(active_menu_item: :settings)
      |> assign(:project, Projects.get_project_with_users!(id))
      |> assign(:users, Lightning.Accounts.list_users())
    else
      put_flash(socket, :error, "You can't access that page")
      |> push_redirect(to: "/")
    end
  end

  defp apply_action(socket, :new, _params) do
    can_create_projects =
      Users |> Permissions.can(:create_projects, socket.assigns.current_user, {})

    if can_create_projects do
      socket
      |> assign(:page_title, "New Project")
      |> assign(active_menu_item: :settings)
      |> assign(:project, %Lightning.Projects.Project{})
      |> assign(:users, Lightning.Accounts.list_users())
    else
      put_flash(socket, :error, "You can't access that page")
      |> push_redirect(to: "/")
    end
  end
end
