defmodule LightningWeb.CredentialLive.KeychainCredentialFormComponent do
  @moduledoc """
  Form Component for working with a single KeychainCredential
  """
  use LightningWeb, :live_component

  alias Lightning.Credentials
  alias Lightning.Policies.Permissions

  @valid_assigns [
    :action,
    :credentials,
    :current_user,
    :from_collab_editor,
    :id,
    :keychain_credential,
    :on_back,
    :on_close,
    :on_save,
    :project,
    :project_user,
    :return_to
  ]

  @impl true
  def mount(socket) do
    {:ok, assign(socket, available_credentials: [])}
  end

  @impl true
  def update(%{project: project, project_user: project_user} = assigns, socket) do
    changeset =
      Credentials.change_keychain_credential(assigns.keychain_credential)

    initial_assigns = Map.filter(assigns, fn {k, _} -> k in @valid_assigns end)

    available_credentials =
      if assigns.project do
        Credentials.list_credentials(assigns.project)
      else
        []
      end

    can_create =
      Permissions.can?(
        :credentials,
        :create_keychain_credential,
        assigns.current_user,
        %{project: project, project_user: project_user}
      )

    can_edit =
      assigns.keychain_credential &&
        Permissions.can?(
          :credentials,
          :edit_keychain_credential,
          assigns.project_user,
          assigns.keychain_credential
        )

    {:ok,
     socket
     |> assign(initial_assigns)
     |> assign(
       changeset: changeset,
       available_credentials: available_credentials,
       can_create: can_create,
       can_edit: can_edit,
       from_collab_editor: Map.get(assigns, :from_collab_editor, false)
     )}
  end

  @impl true
  def handle_event("validate", %{"keychain_credential" => params}, socket) do
    changeset =
      socket.assigns.keychain_credential
      |> Credentials.change_keychain_credential(params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, changeset: changeset)}
  end

  def handle_event("save", %{"keychain_credential" => params}, socket) do
    save_keychain_credential(socket, socket.assigns.action, params)
  end

  attr :id, :string
  attr :action, :atom
  attr :keychain_credential, Lightning.Credentials.KeychainCredential
  attr :project, Lightning.Projects.Project
  attr :credentials, :list, default: []
  attr :project_user, Lightning.Projects.ProjectUser
  attr :return_to, :string
  attr :can_edit, :boolean
  attr :can_create, :boolean

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <Components.Credentials.keychain_credential_form
        id={@id}
        keychain_credential={@keychain_credential}
        keychain_changeset={@changeset}
        available_credentials={@available_credentials}
        myself={@myself}
        action={@action}
        from_collab_editor={@from_collab_editor}
        on_back={JS.push("back_to_advanced_picker", target: @myself)}
        on_modal_close={
          JS.push("close_active_modal",
            target: "#credentials-index-component"
          )
        }
        show_modal={true}
      />
    </div>
    """
  end

  defp save_keychain_credential(socket, :edit, params) do
    if socket.assigns.can_edit do
      case Credentials.update_keychain_credential(
             socket.assigns.keychain_credential,
             params
           ) do
        {:ok, _keychain_credential} ->
          {:noreply,
           socket
           |> put_flash(:info, "Keychain credential updated successfully")
           |> push_event("close_modal", %{id: socket.assigns.id})}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :changeset, changeset)}
      end
    else
      socket =
        socket
        |> put_flash(
          :error,
          "You are not authorized to edit this keychain credential"
        )
        |> push_event("close_modal", %{id: socket.assigns.id})

      {:noreply, socket}
    end
  end

  defp save_keychain_credential(socket, :new, params) do
    if socket.assigns.can_create do
      case Credentials.create_keychain_credential(
             socket.assigns.keychain_credential,
             params
           ) do
        {:ok, keychain_credential} ->
          socket =
            socket
            |> put_flash(:info, "Keychain credential created successfully")

          socket =
            if socket.assigns[:from_collab_editor] do
              socket
            else
              push_event(socket, "close_modal", %{id: socket.assigns.id})
            end

          {:noreply,
           then(socket, fn socket ->
             if socket.assigns[:on_save] do
               socket.assigns[:on_save].(keychain_credential)
             end

             socket
           end)}

        {:error, %Ecto.Changeset{} = changeset} ->
          {:noreply, assign(socket, :changeset, changeset)}
      end
    else
      socket =
        socket
        |> put_flash(
          :error,
          "You are not authorized to create keychain credentials"
        )
        |> push_event("close_modal", %{id: socket.assigns.id})

      {:noreply, socket}
    end
  end
end
