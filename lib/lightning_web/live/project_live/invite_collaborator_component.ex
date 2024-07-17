defmodule LightningWeb.ProjectLive.InviteCollaboratorComponent do
  @moduledoc false
  use LightningWeb, :live_component

  alias Lightning.Projects
  alias Lightning.Projects.ProjectUsersLimiter
  alias LightningWeb.ProjectLive.InvitedCollaborators
  alias Phoenix.LiveView.JS

  @impl true
  def update(assigns, socket) do
    collaborators_data =
      Enum.map(assigns.collaborators, fn %{role: role, email: email} ->
        %{role: role, email: email}
      end)

    collaborators = %InvitedCollaborators{}

    changeset =
      InvitedCollaborators.changeset(collaborators, %{
        invited_collaborators: collaborators_data
      })

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
         {:ok, collaborators} <-
           InvitedCollaborators.validate_collaborators(
             socket.assigns.collaborators,
             params
           ),
         {:ok, _result} <-
           Projects.invite_collaborators(
             socket.assigns.project,
             collaborators,
             socket.assigns.current_user
           ) do
      {:noreply,
       socket
       |> put_flash(
         :info,
         "Invite#{if length(collaborators) > 1, do: "s"} sent successfully"
       )
       |> push_navigate(
         to: ~p"/projects/#{socket.assigns.project}/settings#collaboration"
       )}
    else
      {:error, changeset} ->
        {:noreply, socket |> assign(:changeset, changeset)}

      _error ->
        {:noreply, socket}
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
