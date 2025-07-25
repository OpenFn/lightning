defmodule LightningWeb.CredentialLive.CredentialIndexComponent do
  @moduledoc false
  use LightningWeb, :live_component

  alias Lightning.Credentials
  alias Lightning.Credentials.KeychainCredential
  alias Lightning.OauthClients
  alias Lightning.Policies

  @impl true
  def mount(socket) do
    {:ok,
     assign(socket,
       active_modal: nil,
       can_create_keychain_credential: false,
       can_create_project_credential: false,
       credential: nil,
       credentials: [],
       current_user: nil,
       keychain_credentials: [],
       oauth_client: nil,
       oauth_clients: [],
       project: nil,
       project_user: nil,
       projects: [],
       show_owner_in_tables: false
     )}
  end

  @impl true
  def update(%{current_user: current_user, project: project} = assigns, socket) do
    project_user =
      Lightning.Projects.get_project_user(project, current_user)

    # TODO: reject with permission error if project_user is nil, and add a test for this
    {:ok,
     socket
     |> assign(assigns)
     |> assign(%{
       project_user: project_user,
       can_create_keychain_credential:
         Policies.Permissions.can?(
           :credentials,
           :create_keychain_credential,
           current_user,
           %{project: project, project_user: project_user}
         )
     })
     |> load_credentials()}
  end

  @impl true
  def update(
        %{current_user: _, projects: _, return_to: _} = assigns,
        socket
      ) do
    {:ok,
     socket
     |> assign(assigns)
     |> load_credentials()}
  end

  defp load_credentials(socket) do
    socket
    |> assign(%{
      credentials: list_credentials(socket.assigns.current_user),
      oauth_clients: list_clients(socket.assigns.current_user)
    })
    |> then(fn socket ->
      if is_list(socket.assigns.keychain_credentials) do
        socket
        |> assign(
          :keychain_credentials,
          Lightning.Credentials.list_keychain_credentials_for_project(
            socket.assigns.project
          )
        )
      else
        socket
      end
    end)
  end

  @impl true
  def handle_event("close_active_modal", _params, socket) do
    {:noreply,
     socket
     |> assign(active_modal: nil, credential: nil, oauth_client: nil)
     |> load_credentials()}
  end

  def handle_event("show_modal", %{"target" => "new_credential"}, socket) do
    if socket.assigns.can_create_project_credential do
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
    else
      not_authorized(socket)
    end
  end

  def handle_event(
        "show_modal",
        %{"target" => "new_keychain_credential"},
        socket
      ) do
    # TODO: check if user can create keychain credential
    if socket.assigns.can_create_keychain_credential do
      {:noreply,
       assign(socket,
         active_modal: :new_keychain_credential,
         credential: %KeychainCredential{
           created_by_id: socket.assigns.current_user.id,
           project_id: socket.assigns.project && socket.assigns.project.id
         },
         oauth_client: nil
       )}
    else
      not_authorized(socket)
    end
  end

  def handle_event("show_modal", %{"target" => "new_oauth_client"}, socket) do
    if socket.assigns.can_create_project_credential do
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
    else
      not_authorized(socket)
    end
  end

  def handle_event("edit_oauth_client", %{"id" => client_id}, socket) do
    %{oauth_clients: oauth_clients} = socket.assigns
    client = Enum.find(oauth_clients, fn client -> client.id == client_id end)

    if can_edit_credential(socket.assigns.current_user, client) do
      {:noreply,
       assign(socket,
         active_modal: :edit_oauth_client,
         credential: nil,
         oauth_client: client
       )}
    else
      not_authorized(socket)
    end
  end

  def handle_event("request_oauth_client_deletion", %{"id" => client_id}, socket) do
    %{oauth_clients: oauth_clients} = socket.assigns
    client = Enum.find(oauth_clients, fn client -> client.id == client_id end)

    if can_edit_credential(socket.assigns.current_user, client) do
      {:noreply,
       assign(socket,
         active_modal: :delete_oauth_client,
         credential: nil,
         oauth_client: client
       )}
    else
      not_authorized(socket)
    end
  end

  def handle_event(
        "delete_oauth_client",
        %{"oauth_client_id" => oauth_client_id},
        socket
      ) do
    client = OauthClients.get_client!(oauth_client_id)

    if can_edit_credential(socket.assigns.current_user, client) do
      # TODO: refetch oauth clients
      OauthClients.delete_client(client)

      {:noreply,
       socket
       |> put_flash(:info, "Oauth client deleted")
       |> push_patch(to: socket.assigns.return_to)}
    else
      not_authorized(socket)
    end
  end

  def handle_event("edit_credential", %{"id" => credential_id}, socket) do
    %{credentials: credentials} = socket.assigns
    credential = Enum.find(credentials, fn cred -> cred.id == credential_id end)

    if can_edit_credential(socket.assigns.current_user, credential) do
      {:noreply,
       assign(socket,
         active_modal: :edit_credential,
         credential: credential,
         oauth_client:
           credential.oauth_token && credential.oauth_token.oauth_client
       )}
    else
      not_authorized(socket)
    end
  end

  def handle_event(
        "request_credential_deletion",
        %{"id" => credential_id},
        socket
      ) do
    %{current_user: current_user, credentials: credentials} = socket.assigns
    credential = Enum.find(credentials, &(&1.id == credential_id))

    if credential && can_delete_credential(current_user, credential) do
      {:noreply,
       assign(socket, active_modal: :delete_credential, credential: credential)}
    else
      not_authorized(socket)
    end
  end

  def handle_event(
        "request_credential_transfer",
        %{"id" => credential_id},
        socket
      ) do
    %{current_user: current_user, credentials: credentials} = socket.assigns
    credential = Enum.find(credentials, &(&1.id == credential_id))

    if credential && can_edit_credential(current_user, credential) do
      {:noreply,
       assign(socket, active_modal: :transfer_credential, credential: credential)}
    else
      not_authorized(socket)
    end
  end

  def handle_event(
        "edit_keychain_credential",
        %{"id" => keychain_credential_id},
        socket
      ) do
    %{current_user: current_user, keychain_credentials: keychain_credentials} =
      socket.assigns

    credential =
      Enum.find(keychain_credentials, &(&1.id == keychain_credential_id))

    if credential && can_edit_credential(current_user, credential) do
      {:noreply,
       assign(socket,
         active_modal: :edit_credential,
         credential: credential,
         oauth_client: nil
       )}
    else
      not_authorized(socket)
    end
  end

  def handle_event(
        "request_keychain_credential_deletion",
        %{"id" => keychain_credential_id},
        socket
      ) do
    %{keychain_credentials: keychain_credentials} = socket.assigns

    credential =
      Enum.find(keychain_credentials, &(&1.id == keychain_credential_id))

    if credential &&
         can_delete_credential(socket.assigns.current_user, credential) do
      {:noreply,
       assign(socket,
         active_modal: :delete_keychain_credential,
         credential: credential
       )}
    else
      not_authorized(socket)
    end
  end

  # Deletion happens on this component, and the edit and create happen in
  # the form component.
  def handle_event(
        "delete_keychain_credential",
        %{"keychain_credential_id" => keychain_credential_id},
        socket
      ) do
    %{current_user: current_user} = socket.assigns
    modal_id = "delete-keychain-credential-#{keychain_credential_id}-modal"

    credential =
      Lightning.Credentials.get_keychain_credential(keychain_credential_id)

    if credential && can_delete_credential(current_user, credential) do
      Lightning.Credentials.delete_keychain_credential(credential)
      |> case do
        {:ok, %{id: id}} ->
          {:noreply,
           socket
           |> update(:keychain_credentials, fn credentials ->
             credentials |> Enum.reject(&(&1.id == id))
           end)
           |> push_event("close_modal", %{id: modal_id})
           |> put_flash(:info, "Keychain credential deleted")}

        {:error, _} ->
          {:noreply,
           socket
           |> push_event("close_modal", %{id: modal_id})
           |> put_flash(:error, "Failed to delete keychain credential")}
      end
    else
      not_authorized(socket)
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
     |> push_navigate(to: socket.assigns.return_to)}
  end

  defp can_delete_credential(
         current_user,
         %KeychainCredential{} = keychain_credential
       ) do
    Policies.Permissions.can?(
      :credentials,
      :delete_keychain_credential,
      current_user,
      keychain_credential
    )
  end

  defp can_delete_credential(current_user, credential) do
    Policies.Permissions.can?(
      :users,
      :delete_credential,
      current_user,
      credential
    )
  end

  defp can_edit_credential(
         current_user,
         %KeychainCredential{} = keychain_credential
       ) do
    Policies.Permissions.can?(
      :credentials,
      :edit_keychain_credential,
      current_user,
      keychain_credential
    )
  end

  defp can_edit_credential(current_user, credential) do
    Policies.Permissions.can?(
      Policies.Users,
      :edit_credential,
      current_user,
      credential
    )
  end

  defp not_authorized(socket) do
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
    <Components.Credentials.credential_modal id={@id}>
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
        <Components.Credentials.cancel_button modal_id={@id} />
      </.modal_footer>
    </Components.Credentials.credential_modal>
    """
  end

  defp delete_keychain_credential_modal(assigns) do
    ~H"""
    <Components.Credentials.credential_modal id={@id}>
      <:title>
        Delete Keychain Credential
      </:title>
      <div>
        <p class="text-sm text-gray-500">
          You are about the delete the keychain credential "{@keychain_credential.name}" which may be used in jobs. All jobs using this keychain credential will fail.
          <br /><br />Do you want to proceed with this action?
        </p>
      </div>
      <.modal_footer>
        <.button
          id={"#{@id}_confirm_button"}
          type="button"
          phx-value-keychain_credential_id={@keychain_credential.id}
          phx-click="delete_keychain_credential"
          phx-disable-with="Deleting..."
          theme="danger"
          {assigns |> Map.take([:"phx-target"])}
        >
          Delete
        </.button>
        <Components.Credentials.cancel_button modal_id={@id} />
      </.modal_footer>
    </Components.Credentials.credential_modal>
    """
  end
end
