defmodule LightningWeb.DashboardLive.Index do
  @moduledoc false
  use LightningWeb, :live_view
  alias Lightning.Projects

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(active_menu_item: :projects)}
  end

  # used on mounted and on pushstate loosely equivalent to update/2
  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     apply_action(
       socket,
       socket.assigns.live_action,
       params
     )}
  end

  defp apply_action(socket, :index, _params) do
    project = Projects.first_project_for_user(socket.assigns.current_user)

    if project != nil do
      socket
      |> push_redirect(
        to: Routes.project_workflow_path(socket, :index, project.id)
      )
    else
      socket
      |> assign(:page_title, "Projects")
      |> assign(active_menu_item: :projects)
      |> assign(:projects, nil)
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header socket={@socket}>
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
