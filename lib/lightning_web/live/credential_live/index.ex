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
       page_title: "Credentials",
       table_path: fn query -> ~p"/credentials?#{query}" end
     )}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :index, params) do
    %{current_user: current_user, table_path: table_path} = socket.assigns
    table_params = Helpers.table_params(params)

    credentials_page =
      Credentials.list_credentials(
        current_user,
        Helpers.page_params(table_params, "credentials"),
        Helpers.list_opts(table_params, "credentials")
      )
      |> Helpers.with_credential_display_fields()

    oauth_clients_page =
      OauthClients.list_clients(
        current_user,
        Helpers.page_params(table_params, "oauth_clients"),
        Helpers.list_opts(table_params, "oauth_clients")
      )
      |> Helpers.with_oauth_client_display_fields()

    socket
    |> assign(:credential, nil)
    |> assign(:table_params, table_params)
    |> assign(:credentials_page, credentials_page)
    |> assign(:oauth_clients_page, oauth_clients_page)
    |> assign(
      :credentials_url,
      Helpers.page_url(table_path, table_params, "credentials")
    )
    |> assign(
      :oauth_clients_url,
      Helpers.page_url(table_path, table_params, "oauth_clients")
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
