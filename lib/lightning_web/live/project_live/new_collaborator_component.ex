defmodule LightningWeb.ProjectLive.NewCollaboratorComponent do
  @moduledoc false

  use LightningWeb, :live_component

  alias Lightning.Extensions.UsageLimiting
  alias Lightning.Projects
  alias LightningWeb.ProjectLive.Collaborators
  alias Lightning.Services.UsageLimiter
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
         {:ok, project_users} <- prepare_for_insertion(socket, params),
         {:ok, _} <- add_project_users(socket, project_users) do
      send(self(), :collaborators_updated)
      {:noreply, socket}
    end
  end

  defp prepare_for_insertion(%{assigns: assigns} = socket, params) do
    case Collaborators.prepare_for_insertion(
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
      Collaborators.changeset(socket.assigns.collaborators, params)

    project_users = Ecto.Changeset.get_embed(changeset, :collaborators)

    case UsageLimiter.limit_action(
           %UsageLimiting.Action{
             type: :new_user,
             amount: Enum.count(project_users)
           },
           %UsageLimiting.Context{
             project_id: socket.assigns.project.id
           }
         ) do
      :ok ->
        :ok

      {:error, _reason, %{text: error_text}} ->
        {:noreply, assign(socket, error: error_text)}
    end
  end
end
