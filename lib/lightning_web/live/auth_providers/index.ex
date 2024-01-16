defmodule LightningWeb.AuthProvidersLive.Index do
  @moduledoc """
  LiveView for listing and managing Projects
  """
  use LightningWeb, :live_view

  alias Lightning.AuthProviders
  alias Lightning.Policies.Permissions
  alias Lightning.Policies.Users

  @impl true
  def mount(_params, _session, socket) do
    can_access_admin_space =
      Users
      |> Permissions.can?(:access_admin_space, socket.assigns.current_user, {})

    if can_access_admin_space do
      {:ok,
       socket
       |> assign(:active_menu_item, :authentication),
       layout: {LightningWeb.Layouts, :settings}}
    else
      {:ok,
       put_flash(socket, :nav, :no_access)
       |> push_redirect(to: "/")}
    end
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
    socket
    |> assign(
      auth_provider: AuthProviders.new(),
      redirect_host: LightningWeb.Endpoint.struct_url() |> URI.to_string()
    )
  end

  @impl true
  def render(assigns) do
    ~H"""
    <LayoutComponents.page_content>
      <:header>
        <LayoutComponents.header current_user={@current_user}>
          <:title>Authentication</:title>
        </LayoutComponents.header>
      </:header>
      <LayoutComponents.centered>
        <.live_component
          module={LightningWeb.AuthProvidersLive.FormComponent}
          id={@auth_provider.id || :new}
          auth_provider={@auth_provider}
          redirect_host={@redirect_host}
          parent={self()}
        />
      </LayoutComponents.centered>
    </LayoutComponents.page_content>
    """
  end
end
