defmodule LightningWeb.ProjectLive.Index do
  @moduledoc """
  LiveView for listing and managing Jobs
  """
  use LightningWeb, :live_view

  alias Lightning.Projects

  @impl true
  def mount(_params, _session, socket) do
    case Bodyguard.permit(
           Lightning.Projects.Policy,
           :index,
           socket.assigns.current_user
         ) do
      :ok ->
        {:ok, socket |> assign(:active_menu_item, :projects),
         layout: {LightningWeb.LayoutView, "settings.html"}}

      {:error, :unauthorized} ->
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
    |> assign(:projects, Projects.list_projects())
    |> assign(:page_title, "Projects")
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "New Project")
    |> assign(:project, Projects.get_project_with_users!(id))
    |> assign(:users, Lightning.Accounts.list_users())
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Project")
    |> assign(:project, %Lightning.Projects.Project{})
    |> assign(:users, Lightning.Accounts.list_users())
  end
end
