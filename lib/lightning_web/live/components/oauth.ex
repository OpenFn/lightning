defmodule LightningWeb.Components.Oauth do
  @moduledoc """
  OAuth-related UI components for Lightning credentials.

  This module provides components for OAuth authentication flows, including
  scope selection, user information display, and error handling with
  structured error messages based on validation results.
  """
  use LightningWeb, :component

  alias LightningWeb.Components.Common
  alias LightningWeb.CredentialLive.OAuthErrorFormatter

  @doc """
  Renders a scope selection interface for OAuth permissions.

  This component displays a list of OAuth scopes as checkboxes, allowing users
  to select which permissions they want to grant. Mandatory scopes are automatically
  checked and disabled to prevent deselection.

  ## Attributes

    * `:id` - Unique identifier for the component
    * `:on_change` - Event handler for scope selection changes
    * `:target` - Phoenix LiveView target for events
    * `:selected_scopes` - List of currently selected scope strings
    * `:mandatory_scopes` - List of required scope strings that cannot be deselected
    * `:scopes` - Complete list of available scope strings
    * `:provider` - OAuth provider name (e.g., "Google", "GitHub")
    * `:doc_url` - Optional URL to provider's scope documentation
    * `:disabled` - Whether all checkboxes should be disabled

  ## Examples

      <.scopes_picklist
        id="google-scopes"
        on_change="scope_changed"
        target={@myself}
        selected_scopes={["read", "write"]}
        mandatory_scopes={["read"]}
        scopes={["read", "write", "admin"]}
        provider="Google"
        doc_url="https://developers.google.com/identity/protocols/oauth2/scopes"
        disabled={false}
      />
  """
  attr :id, :string, required: true
  attr :on_change, :any, required: true
  attr :target, :any, required: true
  attr :selected_scopes, :list, required: true
  attr :mandatory_scopes, :list, required: true
  attr :scopes, :list, required: true
  attr :provider, :string, required: true
  attr :doc_url, :string, default: nil
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
          Learn more about {@provider} permissions
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

  @doc """
  Displays a warning alert when the OAuth client configuration is missing.

  This component shows an error message when the OAuth client associated with
  a credential cannot be found, typically due to misconfiguration or deletion.

  ## Examples

      <.missing_client_warning />
  """
  def missing_client_warning(assigns) do
    ~H"""
    <Common.alert type="danger" header="OAuth client not found">
      <:message>
        <p>
          The associated Oauth client for this credential cannot be found. Create
          a new client or contact your administrator.
        </p>
      </:message>
    </Common.alert>
    """
  end

  @doc """
  Renders the OAuth authentication status and flow UI.

  This component manages the complete OAuth authentication flow, displaying
  different UI states based on the authentication progress. It handles initial
  authorization, loading states, success states with user information, and
  various error conditions.

  ## Attributes

    * `:state` - Current authentication state (`:idle`, `:authenticating`, `:fetching_userinfo`, `:complete`, `:error`)
    * `:provider` - OAuth provider name (e.g., "Google", "GitHub")
    * `:myself` - Phoenix LiveView socket reference for event handling
    * `:authorize_url` - OAuth authorization URL (required when state is `:idle` or `:error`)
    * `:userinfo` - User information map from OAuth provider (required when state is `:complete`)
    * `:error` - Error information (required when state is `:error`)
    * `:scopes_changed` - Boolean indicating if selected scopes have changed since last authorization

  ## States

    * `:idle` - Initial state, shows authorize button
    * `:authenticating` - OAuth flow in progress
    * `:fetching_userinfo` - Retrieving user details from provider
    * `:complete` - Successfully authenticated
    * `:error` - Authentication failed

  ## Examples

      <.oauth_status
        state={:complete}
        provider="Google"
        myself={@myself}
        userinfo={%{"name" => "John Doe", "email" => "john@example.com"}}
        scopes_changed={false}
      />

      <.oauth_status
        state={:error}
        provider="GitHub"
        myself={@myself}
        authorize_url="https://github.com/login/oauth/authorize?..."
        error={:invalid_token}
        scopes_changed={false}
      />
  """
  attr :state, :atom, required: true
  attr :provider, :string, required: true
  attr :myself, :any, required: true
  attr :authorize_url, :string, default: nil
  attr :userinfo, :map, default: nil
  attr :error, :any, default: nil
  attr :scopes_changed, :boolean, default: false
  attr :socket, :any, default: nil

  def oauth_status(assigns) do
    ~H"""
    <div class="space-y-4">
      <%= if @scopes_changed do %>
        <.scope_change_alert provider={@provider} myself={@myself} />
      <% else %>
        <%= case @state do %>
          <% :idle -> %>
            <.authorize_button
              authorize_url={@authorize_url}
              provider={@provider}
              myself={@myself}
            />
          <% :authenticating -> %>
            <.text_ping_loader>
              Authenticating with {@provider}...
            </.text_ping_loader>
          <% :fetching_userinfo -> %>
            <.text_ping_loader>
              Fetching user information from {@provider}...
            </.text_ping_loader>
          <% :complete -> %>
            <%= if @userinfo do %>
              <.userinfo_card
                socket={@socket}
                userinfo={@userinfo}
                provider={@provider}
              />
            <% else %>
              <.success_without_userinfo provider={@provider} />
            <% end %>

            <.reauthorize_button provider={@provider} myself={@myself} />
          <% :error -> %>
            <.oauth_error_alert
              error={@error}
              provider={@provider}
              myself={@myself}
              authorize_url={@authorize_url}
            />
        <% end %>
      <% end %>
    </div>
    """
  end

  # Private components

  defp success_without_userinfo(assigns) do
    ~H"""
    <LightningWeb.Components.Common.alert type="success">
      <:message>
        Successfully authenticated with {@provider}!
        Your credential is ready to use, though we couldn't fetch your user information.
      </:message>
    </LightningWeb.Components.Common.alert>
    """
  end

  defp oauth_error_alert(assigns) do
    error_display =
      OAuthErrorFormatter.format_error(assigns.error, assigns.provider)

    alert_type = OAuthErrorFormatter.alert_type(error_display)

    action = %{
      id: "oauth-error-action",
      text: error_display.action_text,
      click: "authorize_click",
      target: assigns.myself
    }

    assigns =
      assigns
      |> assign(:error_display, error_display)
      |> assign(:alert_type, alert_type)
      |> assign(:action, action)

    ~H"""
    <LightningWeb.Components.Common.alert
      type={@alert_type}
      header={@error_display.header}
      actions={[@action]}
    >
      <:message>
        <p>{@error_display.message}</p>
        <%= if @error_display.details do %>
          <p class="mt-2 text-sm whitespace-pre-line">{@error_display.details}</p>
        <% end %>
      </:message>
    </LightningWeb.Components.Common.alert>
    """
  end

  defp scope_change_alert(assigns) do
    error_display =
      OAuthErrorFormatter.format_error(:scope_changed, assigns.provider)

    action = %{
      id: "authorize-button",
      text: error_display.action_text,
      click: "authorize_click",
      target: assigns.myself
    }

    assigns =
      assigns
      |> assign(:error_display, error_display)
      |> assign(:action, action)

    ~H"""
    <LightningWeb.Components.Common.alert
      type="warning"
      header={@error_display.header}
      actions={[@action]}
    >
      <:message>
        <p>{@error_display.message}</p>
        <%= if @error_display.details do %>
          <p class="mt-2 text-sm whitespace-pre-line">{@error_display.details}</p>
        <% end %>
      </:message>
    </LightningWeb.Components.Common.alert>
    """
  end

  defp authorize_button(assigns) do
    assigns =
      assign_new(assigns, :text, fn -> "Sign in with #{assigns.provider}" end)

    ~H"""
    <.button
      id="authorize-button"
      phx-click="authorize_click"
      phx-target={@myself}
      theme="primary"
    >
      <span class="text-normal">{@text}</span>
    </.button>
    """
  end

  defp reauthorize_button(assigns) do
    ~H"""
    <div class="text-sm text-gray-600">
      If your credential is no longer working, you can
      <button
        type="button"
        phx-click="authorize_click"
        phx-target={@myself}
        class="font-medium text-blue-600 hover:text-blue-500"
      >
        reauthenticate with {@provider}
      </button>
    </div>
    """
  end

  defp userinfo_card(assigns) do
    ~H"""
    <div class="bg-green-50 border border-green-200 rounded-lg p-4">
      <div class="flex items-center">
        <img
          src={@userinfo["picture"]}
          alt={@userinfo["name"] || "Unknown"}
          class="h-16 w-16 rounded-full"
          onerror={"this.onerror=null;this.src='#{Routes.static_path(
              @socket,
              "/images/user.png"
            )
          }';"}
        />
        <div class="ml-4">
          <h3 class="text-base font-semibold text-gray-900">
            {@userinfo["name"] || "Unknown User"}
          </h3>
          <p class="text-sm text-gray-600">
            {@userinfo["email"] || "No email provided"}
          </p>
          <p class="text-xs text-green-600 mt-1">
            Successfully authenticated with {@provider}
          </p>
        </div>
      </div>
    </div>
    """
  end
end
