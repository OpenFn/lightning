defmodule LightningWeb.AuthProvidersLive.Index do
  @moduledoc """
  LiveView for listing and managing Projects
  """
  use LightningWeb, :live_view
  alias Lightning.AuthProviders
  alias Lightning.Policies.{Users, Permissions}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(:active_menu_item, :authentication),
     layout: {LightningWeb.LayoutView, :settings}}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, _params) do
    if auth_provider = AuthProviders.get_existing() do
      redirect_host =
        URI.parse(auth_provider.redirect_uri)
        |> URI.merge("/")
        |> URI.to_string()

      socket
      |> assign(auth_provider: auth_provider, redirect_host: redirect_host)
    else
      socket
      |> push_redirect(
        to: Routes.auth_providers_index_path(socket, :new),
        replace: true
      )
    end
  end

  defp apply_action(socket, :new, _params) do
    can_configure_external_auth_provider =
      Users
      |> Permissions.can(
        :configure_external_auth_provider,
        socket.assigns.current_user
      )

    if can_configure_external_auth_provider do
      socket
      |> assign(
        auth_provider: AuthProviders.new(),
        redirect_host: LightningWeb.Endpoint.struct_url() |> URI.to_string()
      )
    else
      put_flash(socket, :error, "You can't access that page")
      |> push_redirect(to: "/")
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <Layout.page_content>
      <:header>
        <Layout.header socket={@socket}>
          <:title>Authentication</:title>
        </Layout.header>
      </:header>
      <Layout.centered>
        <.live_component
          module={LightningWeb.AuthProvidersLive.FormComponent}
          id={@auth_provider.id || :new}
          auth_provider={@auth_provider}
          redirect_host={@redirect_host}
          parent={self()}
        />
      </Layout.centered>
    </Layout.page_content>
    """
  end
end
