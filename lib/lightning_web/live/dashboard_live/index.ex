defmodule LightningWeb.DashboardLive.Index do
  @moduledoc false
  use LightningWeb, :live_view
  alias Lightning.Projects

  @impl true
  def mount(%{"project_id" => project_id}, _session, socket) do
    {:ok,
     socket
     |> assign(
       project: Projects.get_project(project_id),
       active_menu_item: :dashboard
     )}
  end

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:active_menu_item, :dashboard)}
  end

  @impl true
  def handle_params(_, _, socket) do
    {:noreply,
     socket
     |> assign(
       :page_title,
       page_title(socket.assigns.live_action)
     )
     |> assign(
       :projects,
       Projects.get_projects_for_user(socket.assigns.current_user)
     )}
  end

  defp page_title(:index), do: "Dashboard"
end
