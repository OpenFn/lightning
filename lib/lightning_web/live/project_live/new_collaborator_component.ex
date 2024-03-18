defmodule LightningWeb.ProjectLive.NewCollaboratorComponent do
  @moduledoc false

  use LightningWeb, :live_component

  alias Lightning.Projects
  alias LightningWeb.ProjectLive.Collaborators
  alias Phoenix.LiveView.JS

  @impl true
  def update(assigns, socket) do
    collaborators = %Collaborators{}

    changeset = Collaborators.changeset(collaborators, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(collaborators: collaborators, changeset: changeset)}
  end

  @impl true
  def handle_event("validate", %{"project" => params}, socket) do
    changeset =
      Collaborators.changeset(socket.assigns.collaborators, params)

    {:noreply, assign(socket, changeset: changeset)}
  end

  def handle_event(
        "add_collaborators",
        %{"project" => params},
        %{assigns: assigns} = socket
      ) do
    with {:ok, project_users} <-
           Collaborators.prepare_for_insertion(
             assigns.collaborators,
             params,
             assigns.project_users
           ),
         {:ok, _} <-
           Projects.add_project_users(assigns.project, project_users) do
      send(self(), :collaborators_updated)
      {:noreply, socket}
    else
      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end
end
