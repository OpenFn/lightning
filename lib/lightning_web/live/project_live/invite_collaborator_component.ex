defmodule LightningWeb.ProjectLive.InviteCollaboratorComponent do
  @moduledoc false

  require Logger
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
    with :ok <- limit_adding_users(socket, params) do
      case validate_collaborators(socket.assigns.collaborators, params) do
        {:ok, collaborators} ->
          case Projects.invite_collaborators(
                 socket.assigns.project,
                 collaborators,
                 socket.assigns.current_user
               ) do
            {:ok, _result} ->
              {:noreply,
               socket
               |> put_flash(:info, "Invites sent successfully")
               |> push_navigate(
                 to:
                   ~p"/projects/#{socket.assigns.project}/settings#collaboration"
               )}

            {:error, changeset} ->
              Logger.info(
                "Error when inviting users to the project #{socket.assigns.project.name}: #{inspect(changeset)}"
              )

              {:noreply, socket}
          end

        {:error, changeset} ->
          {:noreply, socket |> assign(:changeset, changeset)}
      end
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

  defp validate_collaborators(schema, params) do
    changeset = InvitedCollaborators.changeset(schema, params)

    changeset =
      if changeset.valid? do
        collaborators =
          Ecto.Changeset.get_embed(changeset, :invited_collaborators)

        existing_emails =
          collaborators
          |> Enum.map(&Ecto.Changeset.get_field(&1, :email))
          |> Lightning.Accounts.list_users_by_emails()
          |> Enum.map(& &1.email)

        collaborators =
          Enum.map(collaborators, fn collaborator ->
            collaborator
            |> Ecto.Changeset.validate_change(:email, fn :email, _email ->
              if Ecto.Changeset.get_field(collaborator, :email) in existing_emails do
                [email: "This email is already taken"]
              else
                []
              end
            end)
          end)

        Ecto.Changeset.put_embed(
          changeset,
          :invited_collaborators,
          collaborators
        )
      else
        changeset
      end

    case Ecto.Changeset.apply_action(changeset, :insert) do
      {:ok, %{invited_collaborators: collaborators}} -> {:ok, collaborators}
      {:error, changeset} -> {:error, changeset}
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
