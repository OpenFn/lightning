defmodule LightningWeb.CredentialLive.Index do
  @moduledoc """
  LiveView for listing and managing credentials
  """
  use LightningWeb, :live_view

  alias Lightning.Credentials
  alias Lightning.OauthClients
  alias LightningWeb.CredentialLive.Helpers

  on_mount {LightningWeb.Hooks, :assign_projects}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(
       socket,
       active_menu_item: :credentials,
       page_title: "Credentials"
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    current_user = socket.assigns.current_user
    creds_params = %{"page" => params["credentials_page"] || "1"}
    oauth_params = %{"page" => params["oauth_clients_page"] || "1"}

    credentials_page =
      Credentials.list_credentials(current_user, creds_params)
      |> Helpers.with_credential_display_fields()

    oauth_clients_page =
      OauthClients.list_clients(current_user, oauth_params)
      |> Helpers.with_oauth_client_display_fields()

    socket
    |> assign(:credential, nil)
    |> assign(:credentials_page, credentials_page)
    |> assign(:oauth_clients_page, oauth_clients_page)
    |> assign(
      :credentials_url,
      fn opts ->
        Routes.credential_index_path(socket, :index,
          credentials_page: opts[:page]
        )
      end
    )
    |> assign(
      :oauth_clients_url,
      fn opts ->
        Routes.credential_index_path(socket, :index,
          oauth_clients_page: opts[:page]
        )
      end
    )
  end

  @doc """
  A generic handler for forwarding updates from PubSub
  """
  @impl true
  def handle_info({:forward, mod, opts}, socket) do
    send_update(mod, opts)
    {:noreply, socket}
  end
end
