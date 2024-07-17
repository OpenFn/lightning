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
         {:ok, project_users, new_project_users} <-
           prepare_for_insertion(socket, params),
         {:ok, _project} <- add_project_users(socket, project_users) do
      flash_message = generate_flash_message(project_users, new_project_users)

      return_to = ~p"/projects/#{socket.assigns.project}/settings#collaboration"

      socket = put_flash(socket, :info, flash_message)

      socket =
        if length(new_project_users) > 0 do
          send(self(), {:show_invite_collaborators_modal, new_project_users})
          push_patch(socket, to: return_to)
        else
          push_navigate(socket, to: return_to)
        end

      {:noreply, socket}
    end
  end

  defp generate_flash_message(existing, new) do
    case {length(existing), length(new)} do
      {_, 0} ->
        "Collaborator#{if length(existing) == 1, do: "", else: "s"} added successfully"

      {0, 1} ->
        "This collaborator does not have an OpenFn account. Invite them to join OpenFn and grant access to the project."

      {0, _} ->
        "These collaborators do not have OpenFn accounts. Invite them to join OpenFn and grant them access to the project."

      {existing_count, new_count} ->
        total = existing_count + new_count

        "#{existing_count} out of #{total} collaborator#{if total == 1, do: "", else: "s"} have OpenFn accounts and have been added to your project. You can invite others to join OpenFn and grant them access to this project."
    end
  end

  defp error_field(assigns) do
    ~H"""
    <.error :for={
      msg <-
        Enum.map(
          @field.errors,
          &LightningWeb.CoreComponents.translate_error(&1)
        )
    }>
      <%= msg %>
    </.error>
    """
  end

  defp prepare_for_insertion(%{assigns: assigns} = socket, params) do
    case Collaborators.prepare_for_insertion(
           assigns.collaborators,
           params,
           assigns.project_users
         ) do
      {:ok, project_users} ->
        {project_users, new_project_users} =
          Enum.split_with(project_users, fn pu ->
            Map.get(pu, :user_id) != nil
          end)

        {:ok, project_users, new_project_users}

      {:error, changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end

  defp add_project_users(socket, collaborators) do
    project_users =
      Enum.map(collaborators, fn c ->
        Map.take(c, [:user_id, :role])
      end)

    case Projects.add_project_users(
           socket.assigns.project,
           project_users
         ) do
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
