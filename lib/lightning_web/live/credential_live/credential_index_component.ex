defmodule LightningWeb.CredentialLive.CredentialIndexComponent do
  @moduledoc false
  use LightningWeb, :live_component

  import LightningWeb.CredentialLive.Helpers, only: [can_edit?: 2]

  alias Lightning.Credentials
  alias Lightning.OauthClients

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       active_modal: nil,
       credential: nil,
       oauth_client: nil,
       current_user: nil,
       project: nil,
       credentials: [],
       oauth_clients: [],
       projects: [],
       can_create_project_credential: nil,
       show_owner_in_tables: false
     )}
  end

  @impl true
  def update(
        %{
          current_user: _,
          projects: _,
          can_create_project_credential: _,
          return_to: _
        } =
          assigns,
        socket
      ) do
    # project is only available in the project settings page
    project_or_user = assigns[:project] || assigns.current_user

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:credentials, list_credentials(project_or_user))
     |> assign(:oauth_clients, list_clients(project_or_user))}
  end

  @impl true
  def handle_event("close_active_modal", _params, socket) do
    {:noreply,
     assign(socket, active_modal: nil, credential: nil, oauth_client: nil)}
  end

  def handle_event("new_credential", _params, socket) do
    with :ok <- can_create_project_credential(socket) do
      project_credentials =
        if socket.assigns.project do
          [
            %Lightning.Projects.ProjectCredential{
              project_id: socket.assigns.project.id
            }
          ]
        else
          []
        end

      {:noreply,
       assign(socket,
         active_modal: :new_credential,
         credential: %Lightning.Credentials.Credential{
           user_id: socket.assigns.current_user.id,
           project_credentials: project_credentials
         },
         oauth_client: nil
       )}
    end
  end

  def handle_event("new_oauth_client", _params, socket) do
    with :ok <- can_create_project_credential(socket) do
      project_oauth_clients =
        if socket.assigns.project do
          [
            %Lightning.Projects.ProjectOauthClient{
              project_id: socket.assigns.project.id
            }
          ]
        else
          []
        end

      {:noreply,
       assign(socket,
         active_modal: :new_oauth_client,
         credential: nil,
         oauth_client: %Lightning.Credentials.OauthClient{
           user_id: socket.assigns.current_user.id,
           project_oauth_clients: project_oauth_clients
         }
       )}
    end
  end

  def handle_event("edit_oauth_client", %{"id" => client_id}, socket) do
    %{oauth_clients: oauth_clients} = socket.assigns
    client = Enum.find(oauth_clients, fn client -> client.id == client_id end)

    with :ok <- can_edit_credential(socket, client) do
      {:noreply,
       assign(socket,
         active_modal: :edit_oauth_client,
         credential: nil,
         oauth_client: client
       )}
    end
  end

  def handle_event("request_oauth_client_deletion", %{"id" => client_id}, socket) do
    %{oauth_clients: oauth_clients} = socket.assigns
    client = Enum.find(oauth_clients, fn client -> client.id == client_id end)

    with :ok <- can_edit_credential(socket, client) do
      {:noreply,
       assign(socket,
         active_modal: :delete_oauth_client,
         credential: nil,
         oauth_client: client
       )}
    end
  end

  def handle_event(
        "delete_oauth_client",
        %{"oauth_client_id" => oauth_client_id},
        socket
      ) do
    client = OauthClients.get_client!(oauth_client_id)

    with :ok <- can_edit_credential(socket, client) do
      OauthClients.delete_client(client)

      {:noreply,
       socket
       |> put_flash(:info, "Oauth client deleted")
       |> push_patch(to: socket.assigns.return_to)}
    end
  end

  def handle_event("edit_credential", %{"id" => credential_id}, socket) do
    %{credentials: credentials} = socket.assigns
    credential = Enum.find(credentials, fn cred -> cred.id == credential_id end)

    with :ok <- can_edit_credential(socket, credential) do
      {:noreply,
       assign(socket,
         active_modal: :edit_credential,
         credential: credential,
         oauth_client:
           credential.oauth_token && credential.oauth_token.oauth_client
       )}
    end
  end

  def handle_event(
        "request_credential_deletion",
        %{"id" => credential_id},
        socket
      ) do
    %{credentials: credentials} = socket.assigns
    credential = Enum.find(credentials, fn cred -> cred.id == credential_id end)

    with :ok <- can_delete_credential(socket, credential) do
      {:noreply,
       assign(socket, active_modal: :delete_credential, credential: credential)}
    end
  end

  def handle_event(
        "request_credential_transfer",
        %{"id" => credential_id},
        socket
      ) do
    %{credentials: credentials} = socket.assigns

    credential = Enum.find(credentials, fn cred -> cred.id == credential_id end)

    with :ok <- can_edit_credential(socket, credential) do
      {:noreply,
       assign(socket, active_modal: :transfer_credential, credential: credential)}
    end
  end

  def handle_event(
        "cancel_credential_deletion",
        %{"id" => credential_id},
        socket
      ) do
    Credentials.cancel_scheduled_deletion(credential_id)

    {:noreply,
     socket
     |> put_flash(:info, "Credential deletion canceled")
     |> push_patch(to: socket.assigns.return_to)}
  end

  defp can_delete_credential(socket, credential) do
    can_delete_credential =
      Lightning.Policies.Permissions.can?(
        Lightning.Policies.Users,
        :delete_credential,
        socket.assigns.current_user,
        credential
      )

    if can_delete_credential do
      :ok
    else
      noreply_error(socket)
    end
  end

  defp can_edit_credential(socket, credential) do
    if can_edit?(credential, socket.assigns.current_user) do
      :ok
    else
      noreply_error(socket)
    end
  end

  defp can_create_project_credential(socket) do
    if socket.assigns.can_create_project_credential do
      :ok
    else
      noreply_error(socket)
    end
  end

  defp noreply_error(socket) do
    {:noreply,
     socket
     |> put_flash(:error, "You are not authorized to perform this action")
     |> push_patch(to: socket.assigns.return_to)}
  end

  defp list_credentials(user_or_project) do
    user_or_project
    |> Credentials.list_credentials()
    |> Enum.map(fn c ->
      project_names =
        Map.get(c, :projects, [])
        |> Enum.map(fn p -> p.name end)

      Map.put(c, :project_names, project_names)
    end)
  end

  defp list_clients(user_or_project) do
    user_or_project
    |> OauthClients.list_clients()
    |> Enum.map(fn c ->
      project_names =
        if c.global,
          do: ["GLOBAL"],
          else:
            Map.get(c, :projects, [])
            |> Enum.map(fn p -> p.name end)

      Map.put(c, :project_names, project_names)
    end)
  end

  defp delete_action(assigns) do
    ~H"""
    <%= if @credential.scheduled_deletion do %>
      <.link
        id={"credential-actions-#{@credential.id}-cancel-deletion"}
        href="#"
        phx-click="cancel_credential_deletion"
        phx-value-id={@credential.id}
        phx-target={@myself}
      >
        Cancel deletion
      </.link>
      <.link
        id={"credential-actions-#{@credential.id}-delete-now"}
        phx-click="request_credential_deletion"
        phx-value-id={@credential.id}
        phx-target={@myself}
      >
        Delete now
      </.link>
    <% else %>
      <.link
        id={"credential-actions-#{@credential.id}-delete"}
        phx-click="request_credential_deletion"
        phx-value-id={@credential.id}
        phx-target={@myself}
      >
        Delete
      </.link>
    <% end %>
    """
  end

  defp delete_oauth_client_modal(assigns) do
    ~H"""
    <LightningWeb.Components.Credentials.credential_modal id={@id}>
      <:title>
        Delete Oauth Client
      </:title>
      <div>
        <p class="text-sm text-gray-500">
          You are about the delete the Oauth client "{@client.name}" which may be used in other projects. All jobs dependent on this client will fail.
          <br /><br />Do you want to proceed with this action?
        </p>
      </div>
      <.modal_footer>
        <.button
          id={"#{@id}_confirm_button"}
          type="button"
          phx-value-oauth_client_id={@client.id}
          phx-click="delete_oauth_client"
          phx-disable-with="Deleting..."
          phx-target={@target}
          theme="danger"
        >
          Delete
        </.button>
        <LightningWeb.Components.Credentials.credential_modal_cancel_button modal_id={
          @id
        } />
      </.modal_footer>
    </LightningWeb.Components.Credentials.credential_modal>
    """
  end
end
