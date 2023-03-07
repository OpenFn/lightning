defmodule LightningWeb.CredentialLive.Index do
  @moduledoc """
  LiveView for listing and managing credentials
  """
  use LightningWeb, :live_view

  alias Lightning.Credentials
  alias Lightning.Policies.{Users, Permissions}

  @impl true
  def mount(_params, _session, socket) do
    can_view_credentials =
      Users
      |> Permissions.can(
        :view_credentials,
        socket.assigns.current_user,
        socket.assigns.current_user
      )

    can_edit_credentials =
      Users
      |> Permissions.can(
        :edit_credentials,
        socket.assigns.current_user,
        socket.assigns.current_user
      )

    can_delete_credential =
      Users
      |> Permissions.can(
        :delete_credential,
        socket.assigns.current_user,
        socket.assigns.current_user
      )

    {:ok,
     assign(
       socket,
       :credentials,
       list_credentials(socket.assigns.current_user.id)
     )
     |> assign(:active_menu_item, :credentials)
     |> assign(
       can_view_credentials: can_view_credentials,
       can_edit_credentials: can_edit_credentials,
       can_delete_credential: can_delete_credential
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Credentials")
    |> assign(:credential, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    if socket.assigns.can_delete_credential do
      credential = Credentials.get_credential!(id)

      Credentials.delete_credential(credential)
      |> case do
        {:ok, _} ->
          {:noreply,
           socket
           |> assign(
             :credentials,
             list_credentials(socket.assigns.current_user.id)
           )
           |> put_flash(:info, "Credential deleted successfully")}

        {:error, _changeset} ->
          {:noreply, socket |> put_flash(:error, "Can't delete credential")}
      end
    else
      {:noreply,
       socket
       |> put_flash(:error, "You are not authorized to perform this action.")}
    end
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
end
