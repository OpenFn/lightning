defmodule LightningWeb.CredentialLive.Index do
  @moduledoc """
  LiveView for listing and managing credentials
  """
  use LightningWeb, :live_view

  alias Lightning.Credentials

  on_mount {LightningWeb.Hooks, :assign_projects}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(
       socket,
       credentials: list_credentials(socket.assigns.current_user.id),
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
     |> assign(credentials: list_credentials(socket.assigns.current_user.id))}
  end

  @impl true
  def handle_info({:credential_type_changed, type}, socket) do
    {:noreply, socket |> assign(selected_credential_type: type)}
  end

  @doc """
  A generic handler for forwarding updates from PubSub
  """
  def handle_info({:forward, mod, opts}, socket) do
    send_update(mod, opts)
    {:noreply, socket}
  end

  defp list_credentials(user_id) do
    Credentials.list_credentials_for_user(user_id)
    |> Enum.map(fn c ->
      project_names =
        Map.get(c, :projects, [])
        |> Enum.map_join(", ", fn p -> p.name end)

      Map.put(c, :project_names, project_names)
    end)
  end

  def delete_action(assigns) do
    if assigns.credential.scheduled_deletion do
      ~H"""
      <span>
        <.link
          id={"cancel-deletion-#{@credential.id}"}
          href="#"
          phx-click="cancel_deletion"
          phx-value-id={@credential.id}
        >
          Cancel deletion
        </.link>
      </span>
      |
      <span>
        <.link
          id={"delete-now-#{@credential.id}"}
          navigate={~p"/credentials/#{@credential.id}/delete"}
        >
          Delete now
        </.link>
      </span>
      """
    else
      ~H"""
      <span>
        <.link
          id={"delete-#{@credential.id}"}
          navigate={~p"/credentials/#{@credential.id}/delete"}
        >
          Delete
        </.link>
      </span>
      """
    end
  end
end
