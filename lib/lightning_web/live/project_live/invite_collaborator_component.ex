defmodule LightningWeb.ProjectLive.InviteCollaboratorComponent do
  @moduledoc false

  use LightningWeb, :live_component

  alias Lightning.Projects
  alias Lightning.Projects.ProjectUsersLimiter
  alias LightningWeb.ProjectLive.InvitedCollaborators
  alias Phoenix.LiveView.JS

  @impl true
  def update(assigns, socket) do
    collaborators = %InvitedCollaborators{}

    changeset = InvitedCollaborators.changeset(collaborators, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(collaborators: collaborators, changeset: changeset, error: nil)}
  end

  @impl true
  def handle_event("validate", %{"project" => params}, socket) do
    socket =
      assign(socket,
        changeset:
          InvitedCollaborators.changeset(socket.assigns.collaborators, params)
      )

    with :ok <- limit_adding_users(socket, params) do
      {:noreply, assign(socket, error: nil)}
    end
  end

  def handle_event("add_collaborators", %{"project" => params}, socket) do
    with :ok <- limit_adding_users(socket, params),
         {:ok, project_users} <- prepare_for_insertion(socket, params),
         {:ok, _project} <- add_project_users(socket, project_users) do
      {:noreply,
       socket
       |> put_flash(:info, "Collaborators updated successfully!")
       |> push_navigate(
         to: ~p"/projects/#{socket.assigns.project}/settings#collaboration"
       )}
    end
  end

  defp prepare_for_insertion(%{assigns: assigns} = socket, params) do
    case InvitedCollaborators.prepare_for_insertion(
           assigns.collaborators,
           params,
           assigns.project_users
         ) do
      {:ok, project_users} ->
        {:ok, project_users}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp add_project_users(socket, project_users) do
    case Projects.add_project_users(socket.assigns.project, project_users) do
      {:ok, project} ->
        {:ok, project}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp limit_adding_users(socket, params) do
    changeset =
      InvitedCollaborators.changeset(socket.assigns.collaborators, params)

    project_users = Ecto.Changeset.get_embed(changeset, :invited_collaborators)

    case ProjectUsersLimiter.request_new(
           socket.assigns.project.id,
           Enum.count(project_users)
         ) do
      :ok ->
        :ok

      {:error, _reason, %{text: error_text}} ->
        {:noreply, assign(socket, error: error_text)}
    end
  end
end
