defmodule LightningWeb.CredentialLive.Index do
  @moduledoc """
  LiveView for listing and managing credentials
  """
  use LightningWeb, :live_view

  alias Lightning.Credentials

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(
       socket,
       :credentials,
       list_credentials(socket.assigns.current_user.id)
     )
     |> assign(:active_menu_item, :credentials)}
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
    credential = Credentials.get_credential!(id)
    {:ok, _} = Credentials.delete_credential(credential)

    {:noreply,
     assign(
       socket,
       :credentials,
       list_credentials(socket.assigns.current_user.id)
     )}
  end

  defp list_credentials(user_id) do
    Credentials.list_credentials_for_user(user_id)
  end
end
