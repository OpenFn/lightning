defmodule LightningWeb.Components.Oauth do
  @moduledoc false
  use LightningWeb, :component

  alias LightningWeb.Components.Common

  attr :id, :string, required: true
  attr :on_change, :any, required: true
  attr :target, :any, required: true
  attr :selected_scopes, :any, required: true
  attr :mandatory_scopes, :any, required: true
  attr :scopes, :any, required: true
  attr :provider, :string, required: true
  attr :doc_url, :any, default: nil
  attr :disabled, :boolean, default: false

  def scopes_picklist(assigns) do
    ~H"""
    <div id={@id} class="mt-5">
      <h3 class="leading-6 text-slate-800 pb-2 mb-2">
        <div class="flex flex-row text-sm font-semibold">
          Select permissions
          <LightningWeb.Components.Common.tooltip
            id={"#{@id}-tooltip"}
            title="Select permissions associated to your OAuth2 Token"
          />
        </div>
        <div :if={@doc_url} class="flex flex-row text-xs mt-1">
          Learn more about <%= @provider %> permissions
          <a
            target="_blank"
            href={@doc_url}
            class="whitespace-nowrap font-medium text-blue-700 hover:text-blue-600"
          >
            &nbsp;here
          </a>
        </div>
      </h3>
      <div class="flex flex-wrap gap-1">
        <%= for scope <- @scopes do %>
          <.input
            id={"#{@id}_#{scope}"}
            type="checkbox"
            name={scope}
            value={scope}
            checked={scope in @selected_scopes or scope in @mandatory_scopes}
            disabled={scope in @mandatory_scopes || @disabled}
            phx-change={@on_change}
            phx-target={@target}
            label={scope}
          /> &nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;
        <% end %>
      </div>
    </div>
    """
  end

  def authorize_button(assigns) do
    ~H"""
    <.link
      href={@authorize_url}
      id="authorize-button"
      phx-click="authorize_click"
      phx-target={@myself}
      target="_blank"
      class="rounded-md bg-indigo-600 px-3.5 py-2.5 text-sm font-semibold text-white shadow-sm hover:bg-indigo-500 focus-visible:outline focus-visible:outline-2 focus-visible:outline-offset-2 focus-visible:outline-indigo-600"
    >
      <span class="text-normal">Sign in with <%= @provider %></span>
    </.link>
    """
  end

  def userinfo(assigns) do
    ~H"""
    <div class="flex flex-wrap items-center justify-between sm:flex-nowrap mt-5">
      <div class="flex items-center">
        <img
          src={@userinfo["picture"]}
          class="h-20 w-20 rounded-full"
          alt={@userinfo["name"]}
          onerror={"this.onerror=null;this.src='#{Routes.static_path(
              @socket,
              "/images/user.png"
            )
          }';"}
        />
        <div class="ml-4">
          <h3 class="text-base font-semibold leading-6 text-gray-900">
            <%= @userinfo["name"] %>
          </h3>
          <p class="text-sm text-gray-500">
            <a href="#"><%= @userinfo["email"] %></a>
          </p>
        </div>
      </div>
    </div>
    """
  end

  def success_message(%{revocation: :available} = assigns) do
    ~H"""
    <Common.alert type="success">
      <:message>
        Success. If your credential is no longer working, you may try to revoke and reauthenticate by clicking
        <.reauthorize_button id="re-authorize-button" target={@myself}>
          here.
        </.reauthorize_button>
      </:message>
    </Common.alert>
    """
  end

  def success_message(%{revocation: :unavailable} = assigns) do
    ~H"""
    <Common.alert type="success">
      <:message>
        Success. If your credential is no longer working, you may try to revoke OpenFn access and and reauthenticate. To revoke access, go to the third party apps section of the provider's website or portal.
      </:message>
    </Common.alert>
    """
  end

  defp reauthorize_button(assigns) do
    ~H"""
    <.link
      id={@id}
      href="#"
      phx-target={@target}
      phx-click="re_authorize_click"
      class="hover:underline text-primary-900"
    >
      <%= render_slot(@inner_block) %>
    </.link>
    """
  end

  def error_block(%{type: :token_failed} = assigns) do
    ~H"""
    <Common.alert type="warning" header="Something went wrong.">
      <:message>
      Failed retrieving the token from the provider. Please try again
        <.reauthorize_button id="re-authorize-button" target={@myself}>
          here
        </.reauthorize_button>
      </:message>
    </Common.alert>
    """
  end

  def error_block(%{type: :revoke_failed} = assigns) do
    ~H"""
    <Common.alert type="danger" header="Something went wrong.">
      <:message>
      Token revocation failed. The token associated with this credential may
      have already been revoked or expired. Please delete this credential and
      create a new one.
      </:message>
    </Common.alert>
    """
  end

  def error_block(%{type: :refresh_failed} = assigns) do
    ~H"""
    <Common.alert type="warning" header="Something went wrong.">
      <:message>
        Failed renewing your access token. Please request a new token by clicking
        <.reauthorize_button id="re-authorize-button" target={@myself}>
          here
        </.reauthorize_button>
      </:message>
    </Common.alert>
    """
  end

  def error_block(%{type: :userinfo_failed} = assigns) do
    ~H"""
    <Common.alert
      type="info"
      actions={[{"Try again", "try_userinfo_again", @myself}]}
    >
      <:message>
      That seemed to work, but we couldn't fetch your user information. You can
      save your credential now or try again.
      </:message>
    </Common.alert>
    """
  end

  def error_block(%{type: :missing_required} = assigns) do
    ~H"""
    <Common.alert type="danger" header="Missing refresh token">
      <:message>
      We didn't receive a refresh token from this provider. Sometimes this happens
      if you have already granted access to OpenFn via another credential. If you
      have another credential, please use that one. If you don't, please revoke
      OpenFn's access to your provider via the "third party apps" section of their
      website. Once that is done, you can try to reauthorize
        <.reauthorize_button id="re-authorize-button" target={@myself}>
          here
        </.reauthorize_button>
      </:message>
    </Common.alert>
    """
  end

  def error_block(%{type: :code_failed} = assigns) do
    ~H"""
    <Common.alert type="danger" header="Something went wrong.">
      <:message>
        Failed retrieving authentication code. Please reauthorize
        <.reauthorize_button id="re-authorize-button" target={@myself}>
          here
        </.reauthorize_button>
      </:message>
    </Common.alert>
    """
  end

  def missing_client_warning(assigns) do
    ~H"""
    <Common.alert type="danger" header="OAuth client not found">
      <:message>
      The associated Oauth client for this credential cannot be found. Create a new client or contact your administrator.
      </:message>
    </Common.alert>
    """
  end

  def reauthorize_banner(assigns) do
    ~H"""
    <Common.alert type="info">
      <:message>
      Please reauthenticate to save your credential with the updated scopes by clicking
      <.reauthorize_button id="re-authorize-button" target={@myself}>
        here <span aria-hidden="true"> &rarr;</span>
      </.reauthorize_button>
      </:message>
    </Common.alert>
    """
  end
end
