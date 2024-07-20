defmodule LightningWeb.DashboardLive.Index do
  @moduledoc false
  use LightningWeb, :live_view

  # alias Lightning.Policies.Permissions
  # alias Lightning.Policies.ProjectUsers
  # alias Lightning.Projects

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(active_menu_item: :projects)}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, push_redirect(socket, to: ~p"/projects")}
  end

  # defp apply_action(socket, :index, _params) do
  #   projects =
  #     Projects.get_projects_for_user(socket.assigns.current_user) |> IO.inspect()

  #   if Enum.empty?(projects) do
  #     socket
  #     |> assign(:page_title, "Projects")
  #     |> assign(active_menu_item: :projects)
  #     |> assign(:projects, nil)
  #   else
  #     # can_access_project =
  #     #   ProjectUsers
  #     #   |> Permissions.can?(
  #     #     :access_project,
  #     #     socket.assigns.current_user,
  #     #     project
  #     #   )

  #     # if can_access_project do
  #     # socket
  #     # |> push_redirect(to: ~p"/projects/#{project.id}/w")
  #     socket
  #     |> push_redirect(to: ~p"/projects")

  #     # else
  #     # {:halt, redirect(socket, to: "/") |> put_flash(:nav, :not_found)}
  #     # end
  #   end
  # end

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header current_user={@current_user}>
          <:title><%= @page_title %></:title>
        </LayoutComponents.header>
      </:header>
      <div class="max-w-7xl mx-auto py-6 sm:px-6 lg:px-8">
        No projects found. If this seems odd, contact your instance administrator.
      </div>
    </LayoutComponents.page_content>
    """
  end
end
