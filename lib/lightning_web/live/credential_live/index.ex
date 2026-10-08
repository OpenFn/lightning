defmodule LightningWeb.CredentialLive.Index do
  @moduledoc """
  LiveView for listing and managing credentials
  """
  use LightningWeb, :live_view

  alias Lightning.Credentials
  alias Lightning.OauthClients

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
      |> map_credentials()

    oauth_clients_page =
      OauthClients.list_clients(current_user, oauth_params)
      |> map_oauth_clients()

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

  defp map_credentials(%Scrivener.Page{} = page) do
    %{page | entries: Enum.map(page.entries, &add_credential_display_fields/1)}
  end

  defp add_credential_display_fields(credential) do
    project_names = Map.get(credential, :projects, []) |> Enum.map(& &1.name)

    environment_names =
      credential |> Map.get(:credential_bodies, []) |> Enum.map(& &1.name)

    credential
    |> Map.put(:project_names, project_names)
    |> Map.put(:environment_names, environment_names)
  end

  defp map_oauth_clients(%Scrivener.Page{} = page) do
    %{page | entries: Enum.map(page.entries, &add_oauth_client_display_fields/1)}
  end

  defp add_oauth_client_display_fields(client) do
    project_names =
      if client.global,
        do: ["GLOBAL"],
        else: Map.get(client, :projects, []) |> Enum.map(& &1.name)

    Map.put(client, :project_names, project_names)
  end
end
