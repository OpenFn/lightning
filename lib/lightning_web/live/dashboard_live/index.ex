defmodule LightningWeb.DashboardLive.Index do
  @moduledoc false
  use LightningWeb, :live_view
  alias Lightning.Projects

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(active_menu_item: :projects)}
  end

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
    <Layout.page_content>
      <:header>
        <Layout.header title={@page_title} socket={@socket}>
          <%= if assigns[:project] do %>
            <.link navigate={
              Routes.project_job_index_path(@socket, :index, @project.id)
            }>
              <div class="inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-secondary-200 hover:bg-secondary-300 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-secondary-500">
                <div class="h-full">
                  <Heroicons.table_cells solid class="h-4 w-4 inline-block" />
                </div>
              </div>
            </.link>
          <% end %>
        </Layout.header>
      </:header>
      <div class="max-w-7xl mx-auto py-6 sm:px-6 lg:px-8">
        No projects found. If this seems odd, contact your instance administrator.
      </div>
    </Layout.page_content>
    """
  end
end
