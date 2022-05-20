defmodule LightningWeb.CredentialLive.Index do
  @moduledoc """
  LiveView for listing and managing Jobs
  """
  use LightningWeb, :live_view

  alias Lightning.Credentials
  alias Lightning.Credentials.Credential

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, :credentials, list_credentials())
     |> assign(:active_menu_item, :credentials)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Credential")
    |> assign(:credential, Credentials.get_credential!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Credential")
    |> assign(:credential, %Credential{user_id: socket.assigns.current_user.id})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Credentials")
    |> assign(:credential, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    credential = Credentials.get_credential!(id)
    {:ok, _} = Credentials.delete_credential(credential)

    {:noreply, assign(socket, :credentials, list_credentials())}
  end

  defp list_credentials do
    Credentials.list_credentials()
  end
end
