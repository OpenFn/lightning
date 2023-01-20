defmodule LightningWeb.ProjectLive.Settings do
  @moduledoc """
  Index Liveview for Runs
  """
  use LightningWeb, :live_view

  alias Lightning.Projects

  on_mount({LightningWeb.Hooks, :project_scope})

  @impl true
  def mount(_params, _session, socket) do
    can_edit_project =
      case Bodyguard.permit(
             Lightning.Projects.Policy,
             :edit,
             socket.assigns.current_user,
             socket.assigns.project
           ) do
        :ok -> true
        {:error, :unauthorized} -> false
      end

    {:ok,
     socket
     |> assign(
       active_menu_item: :settings,
       can_edit_project: can_edit_project,
       changeset: Projects.change_project(socket.assigns.project)
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, socket |> apply_action(socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket |> assign(:page_title, "Project settings")
  end

  @impl true
  def handle_event("validate", %{"project" => project_params} = _params, socket) do
    changeset =
      socket.assigns.project
      |> Projects.change_project(project_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"project" => project_params} = _params, socket) do
    save_project(socket, project_params)
  end

  defp save_project(socket, project_params) do
    case Projects.update_project(socket.assigns.project, project_params) do
      {:ok, project} ->
        {:noreply,
         socket
         |> assign(:project, project)
         |> put_flash(:info, "Project updated successfully")}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end
end
