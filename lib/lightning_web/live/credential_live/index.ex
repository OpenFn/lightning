defmodule LightningWeb.CredentialLive.Index do
  @moduledoc """
  LiveView for listing and managing credentials
  """
  use LightningWeb, :live_view

  import LightningWeb.CredentialLive.Helpers, only: [can_edit?: 2]

  alias Lightning.Credentials
  alias Lightning.OauthClients
  alias LightningWeb.Components.Common

  on_mount {LightningWeb.Hooks, :assign_projects}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(
       socket,
       current_user: socket.assigns.current_user,
       credentials: list_credentials(socket.assigns.current_user),
       oauth_clients: list_clients(socket.assigns.current_user),
       active_menu_item: :credentials,
       selected_credential_type: nil,
       page_title: "Credentials"
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(credential: nil)
  end

  defp apply_action(socket, :delete, %{"id" => id}) do
    credential = Credentials.get_credential!(id)

    can_delete_credential =
      Lightning.Policies.Users
      |> Lightning.Policies.Permissions.can?(
        :delete_credential,
        socket.assigns.current_user,
        credential
      )

    if can_delete_credential do
      socket |> assign(credential: credential)
    else
      socket
      |> put_flash(:error, "You can't perform this action")
      |> push_patch(to: ~p"/credentials")
    end
  end

  @impl true
  def handle_event(
        "cancel_deletion",
        %{"id" => credential_id},
        socket
      ) do
    Credentials.cancel_scheduled_deletion(credential_id)

    {:noreply,
     socket
     |> put_flash(:info, "Credential deletion canceled")
     |> push_patch(to: ~p"/credentials")
     |> assign(credentials: list_credentials(socket.assigns.current_user))}
  end

  def handle_event(
        "delete_oauth_client",
        %{"oauth_client_id" => oauth_client_id},
        socket
      ) do
    OauthClients.get_client!(oauth_client_id) |> OauthClients.delete_client()

    {:noreply,
     socket
     |> put_flash(:info, "Oauth client deleted")
     |> assign(:oauth_clients, list_clients(socket.assigns.current_user))
     |> push_patch(to: ~p"/credentials")}
  end

  @doc """
  A generic handler for forwarding updates from PubSub
  """
  @impl true
  def handle_info({:forward, mod, opts}, socket) do
    send_update(mod, opts)
    {:noreply, socket}
  end

  defp list_credentials(user) do
    Credentials.list_credentials(user)
    |> Enum.map(fn c ->
      project_names =
        Map.get(c, :projects, [])
        |> Enum.map(fn p -> p.name end)

      Map.put(c, :project_names, project_names)
    end)
  end

  defp list_clients(user) do
    OauthClients.list_clients(user)
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

  def delete_action(assigns) do
    ~H"""
    <%= if @credential.scheduled_deletion do %>
      <.link
        id={"cancel-deletion-#{@credential.id}"}
        href="#"
        phx-click="cancel_deletion"
        phx-value-id={@credential.id}
      >
        Cancel deletion
      </.link>
      <.link
        id={"delete-now-#{@credential.id}"}
        navigate={~p"/credentials/#{@credential.id}/delete"}
      >
        Delete now
      </.link>
    <% else %>
      <.link
        id={"delete-#{@credential.id}"}
        navigate={~p"/credentials/#{@credential.id}/delete"}
      >
        Delete
      </.link>
    <% end %>
    """
  end
end
