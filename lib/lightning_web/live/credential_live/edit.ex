defmodule LightningWeb.CredentialLive.Edit do
  @moduledoc """
  LiveView for editing a single Credential, which inturn uses
  `LightningWeb.CredentialLive.FormComponent` for common functionality.
  """
  use LightningWeb, :live_view

  alias Lightning.Credentials
  alias Lightning.Projects

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, "Show Job")
     |> assign(:active_menu_item, :credentials)
     |> assign(
       credential:
         Credentials.get_credential!(id)
         |> Lightning.Repo.preload(:project_credentials),
       projects: Projects.get_projects_for_user(socket.assigns.current_user)
     )}
  end
end
