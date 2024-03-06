defmodule LightningWeb.ProjectLive.NewCollaboratorComponent do
  @moduledoc false

  use LightningWeb, :live_component

  alias Lightning.Accounts.UserNotifier
  alias Lightning.Projects
  alias LightningWeb.ProjectLive.CollaboratorProject
  alias Phoenix.LiveView.JS

  @impl true
  def update(assigns, socket) do
    collaborator_project = %CollaboratorProject{}

    changeset = CollaboratorProject.changeset(collaborator_project, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(collaborator_project: collaborator_project, changeset: changeset)}
  end

  @impl true
  def handle_event("validate", %{"project" => params}, socket) do
    changeset =
      CollaboratorProject.changeset(socket.assigns.collaborator_project, params)

    {:noreply, assign(socket, changeset: changeset)}
  end

  def handle_event(
        "add_collaborators",
        %{"project" => params},
        %{assigns: assigns} = socket
      ) do
    with {:ok, project_users} <-
           CollaboratorProject.prepare_for_insertion(
             assigns.collaborator_project,
             params,
             assigns.project_users
           ),
         {:ok, updated_project} <-
           Projects.update_project(%{assigns.project | project_users: []}, %{
             project_users: project_users
           }) do
      send(self(), :collaborators_updated)
      send_email_to_users(updated_project, updated_project.project_users)
      {:noreply, socket}
    else
      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp send_email_to_users(project, project_users) do
    project_users = Lightning.Repo.preload(project_users, [:user])

    Enum.map(project_users, fn project_user ->
      UserNotifier.deliver_project_addition_notification(
        project_user.user,
        project
      )
    end)
  end
end
