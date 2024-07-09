defmodule LightningWeb.ProjectLive.NewCollaboratorComponent do
  @moduledoc false

  use LightningWeb, :live_component

  alias Lightning.Projects
  alias Lightning.Projects.ProjectUsersLimiter
  alias LightningWeb.ProjectLive.Collaborators
  alias Phoenix.LiveView.JS

  @impl true
  def update(assigns, socket) do
    collaborators = %Collaborators{}

    changeset = Collaborators.changeset(collaborators, %{})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(collaborators: collaborators, changeset: changeset, error: nil)}
  end

  @impl true
  def handle_event("validate", %{"project" => params}, socket) do
    socket =
      assign(socket,
        changeset: Collaborators.changeset(socket.assigns.collaborators, params)
      )

    with :ok <- limit_adding_users(socket, params) do
      {:noreply, assign(socket, error: nil)}
    end
  end

  def handle_event("add_collaborators", %{"project" => params}, socket) do
    with :ok <- limit_adding_users(socket, params),
         {:ok, %{collaborators: project_users, to_invite: users_to_invite}} <-
           prepare_for_insertion(socket, params),
         {:ok, _project} <- add_project_users(socket, project_users) do
      n_project_users = length(project_users)
      n_to_invite = length(users_to_invite)
      total = n_project_users + n_to_invite

      message =
        "#{n_project_users} out of #{total} collaborators have OpenFn accounts and have been added to your project. You can invite others to join OpenFn and grant them access to this project."

      {:noreply,
       socket
       |> put_flash(:info, message)
       |> push_navigate(
         to: ~p"/projects/#{socket.assigns.project}/settings#collaboration"
       )}
    end
  end

  defp prepare_for_insertion(%{assigns: assigns} = socket, params) do
    case Collaborators.prepare_for_insertion(
           assigns.collaborators,
           params,
           assigns.project_users
         ) do
      {:ok, %{collaborators: project_users, to_invite: non_project_users}} ->
        {:ok, %{collaborators: project_users, to_invite: non_project_users}}

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
      Collaborators.changeset(socket.assigns.collaborators, params)

    project_users = Ecto.Changeset.get_embed(changeset, :collaborators)

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
