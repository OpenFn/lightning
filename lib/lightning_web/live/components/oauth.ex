defmodule LightningWeb.Components.Oauth do
  @moduledoc """
  OAuth-related UI components for Lightning credentials.

  This module provides components for OAuth authentication flows, including
  scope selection, user information display, and error handling with
  structured error messages based on validation results.
  """
  use LightningWeb, :component

  import Ecto.Changeset, only: [get_field: 2]

  alias LightningWeb.Components.Common

  @type provider :: String.t() | nil

  defmodule ActionButton do
    @moduledoc """
    Represents an action button configuration for OAuth alerts.
    """

    @type t :: %__MODULE__{
            id: String.t(),
            text: String.t(),
            target: any(),
            click: String.t()
          }

    defstruct [:id, :text, :target, :click]

    @spec new(String.t(), String.t(), any(), String.t()) :: t()
    def new(id, text, target, click)
        when is_binary(id) and is_binary(text) and is_binary(click) do
      %__MODULE__{
        id: id,
        text: text,
        target: target,
        click: click
      }
    end
  end

  defmodule ErrorResponse do
    @moduledoc """
    Represents the categorized error response with header, action type, and message.
    """

    @type t :: %__MODULE__{
            header: String.t(),
            action: atom(),
            message: String.t()
          }

    defstruct [:header, :action, :message]

    @spec new(String.t(), atom(), String.t()) :: t()
    def new(header, action, message) do
      %__MODULE__{
        header: header,
        action: action,
        message: message
      }
    end
  end

  @doc """
  Renders a scope selection interface for OAuth permissions.
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
  Renders an OAuth authorization button.
  """
  attr :authorize_url, :string, required: true
  attr :myself, :any, required: true
  attr :provider, :string, required: true

  def authorize_button(assigns) do
    ~H"""
    <.button_link
      href={@authorize_url}
      id="authorize-button"
      phx-click="authorize_click"
      phx-target={@myself}
      target="_blank"
      theme="primary"
    >
      <span class="text-normal">Sign in with {@provider}</span>
    </.button_link>
    """
  end

  @doc """
  Displays OAuth user information with avatar and details.
  """
  attr :userinfo, :map, required: true
  attr :myself, :any, required: true
  attr :authorize_url, :any, required: true
  attr :socket, :any, required: true

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
            {@userinfo["name"]}
          </h3>
          <p class="text-sm text-gray-500">
            <a href="#">{@userinfo["email"]}</a>
          </p>
        </div>
      </div>
    </div>
    """
  end

  @doc """
  Renders success messages with optional reauthorization links.
  """
  attr :revocation, :atom, required: true, values: [:available, :unavailable]
  attr :myself, :any, required: true

  def success_message(%{revocation: :available} = assigns) do
    ~H"""
    <Common.alert type="success">
      <:message>
        Success. If your credential is no longer working, you may try to revoke and reauthenticate by clicking
        <.reauthorize_button
          id="re-authorize-button"
          class="link-success"
          target={@myself}
        >
          here <span aria-hidden="true"> &rarr;</span>
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

  @doc """
  Renders a banner prompting users to reauthenticate when scopes have changed.
  """
  attr :provider, :string, required: true
  attr :authorize_url, :any, required: true
  attr :revocation_endpoint, :any, default: nil
  attr :myself, :any, required: true

  def reauthorize_banner(assigns) do
    action =
      create_auth_action(
        assigns.myself,
        "Reauthenticate with #{assigns.provider}"
      )

    assigns = assign(assigns, :action, Map.from_struct(action))

    ~H"""
    <Common.alert
      id="re-authorize-banner"
      type="warning"
      header="Reauthentication required"
      actions={[@action]}
    >
      <:message>
        <p>
          You've changed the scopes (i.e., permissions) on this credential. To save, you must first reauthenticate with your OAuth2 client.
        </p>
      </:message>
    </Common.alert>
    """
  end

  @doc """
  Displays a warning when OAuth client configuration is missing.
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
  Renders structured error alerts based on OAuth validation results.

  This function provides intelligent error handling by extracting structured
  error information from Ecto changesets and presenting appropriate user
  guidance and action buttons.
  """
  attr :type, :atom, required: true
  attr :changeset, :any, default: nil
  attr :provider, :string, default: nil
  attr :authorize_url, :string, default: nil
  attr :myself, :any, required: true
  attr :revocation_endpoint, :any, default: nil

  def alert_block(%{type: :missing_required} = assigns) do
    oauth_error_type = get_field(assigns.changeset, :oauth_error_type)
    oauth_error_details = get_field(assigns.changeset, :oauth_error_details)

    error_message = get_oauth_error_message(assigns.changeset)

    %ErrorResponse{
      header: header,
      action: suggested_action,
      message: user_message
    } =
      categorize_oauth_error_by_type(
        oauth_error_type,
        oauth_error_details,
        assigns[:provider]
      )

    action = determine_action_button(assigns, suggested_action)

    assigns =
      assigns
      |> assign(:action, Map.from_struct(action))
      |> assign(:header, header)
      |> assign(:error_message, error_message)
      |> assign(:user_message, user_message)

    ~H"""
    <Common.alert type="danger" header={@header} actions={[@action]}>
      <:message>
        <p>{@error_message}</p>
        <p>{@user_message}</p>
      </:message>
    </Common.alert>
    """
  end

  def alert_block(%{type: :token_failed} = assigns) do
    action = create_reauth_action(assigns.myself, "Try again")
    assigns = assign(assigns, :action, Map.from_struct(action))

    ~H"""
    <Common.alert type="warning" header="Something went wrong." actions={[@action]}>
      <:message>
        <p>Failed retrieving the token from the provider.</p>
      </:message>
    </Common.alert>
    """
  end

  def alert_block(%{type: :refresh_failed} = assigns) do
    action = create_reauth_action(assigns.myself, "Request new token")
    assigns = assign(assigns, :action, Map.from_struct(action))

    ~H"""
    <Common.alert type="warning" header="Something went wrong." actions={[@action]}>
      <:message>
        <p>Failed renewing your access token.</p>
      </:message>
    </Common.alert>
    """
  end

  def alert_block(%{type: :userinfo_failed} = assigns) do
    action = create_userinfo_retry_action(assigns.myself)
    assigns = assign(assigns, :action, Map.from_struct(action))

    ~H"""
    <Common.alert type="info" actions={[@action]}>
      <:message>
        <p>
          That worked, but we couldn't fetch your user information.
          You can save your credential now or try again.
        </p>
      </:message>
    </Common.alert>
    """
  end

  def alert_block(%{type: :code_failed} = assigns) do
    action = create_reauth_action(assigns.myself, "Reauthorize")
    assigns = assign(assigns, :action, Map.from_struct(action))

    ~H"""
    <Common.alert type="danger" header="Something went wrong." actions={[@action]}>
      <:message>
        <p>Failed retrieving authentication code.</p>
      </:message>
    </Common.alert>
    """
  end

  def alert_block(%{type: :revoke_failed} = assigns) do
    action = create_auth_action(assigns.myself, "Authorize again")
    assigns = assign(assigns, :action, Map.from_struct(action))

    ~H"""
    <Common.alert type="danger" header="Something went wrong." actions={[@action]}>
      <:message>
        Token revocation failed. The token associated with this credential may
        have already been revoked or expired. You may try to authorize again,
        or delete this credential and create a new one.
      </:message>
    </Common.alert>
    """
  end

  def alert_block(%{type: :fetching_userinfo} = assigns) do
    ~H"""
    <.text_ping_loader>
      Attempting to fetch user information from your OAuth provider
    </.text_ping_loader>
    """
  end

  defp create_reauth_action(target, text) do
    ActionButton.new("re-authorize-button", text, target, "re_authorize_click")
  end

  defp create_auth_action(target, text) do
    ActionButton.new("authorize-button", text, target, "authorize_click")
  end

  defp create_userinfo_retry_action(target) do
    ActionButton.new(
      "try-userinfo-button",
      "Try again",
      target,
      "try_userinfo_again"
    )
  end

  defp reauthorize_button(assigns) do
    assigns =
      assigns
      |> assign_new(:class, fn -> "" end)
      |> assign(:button_class, "link #{assigns.class}")

    ~H"""
    <button
      id={@id}
      type="button"
      phx-target={@target}
      phx-click="re_authorize_click"
      class={@button_class}
    >
      {render_slot(@inner_block)}
    </button>
    """
  end

  @spec get_oauth_error_message(Ecto.Changeset.t()) :: String.t()
  defp get_oauth_error_message(changeset)
       when is_struct(changeset, Ecto.Changeset) do
    case Keyword.get(changeset.errors, :oauth_token) do
      {message, _} when is_binary(message) -> message
      _ -> "OAuth authorization failed"
    end
  end

  defp get_oauth_error_message(_), do: "OAuth authorization failed"

  @spec categorize_oauth_error_by_type(
          atom() | nil,
          map() | nil,
          provider()
        ) :: ErrorResponse.t()
  defp categorize_oauth_error_by_type(nil, _error_details, provider) do
    ErrorResponse.new(
      "OAuth Error",
      :generic,
      build_generic_message(provider)
    )
  end

  defp categorize_oauth_error_by_type(error_type, error_details, provider) do
    case error_type do
      :missing_scopes ->
        handle_missing_scopes_error(error_details, provider)

      :missing_refresh_token ->
        handle_missing_refresh_token_error(error_details, provider)

      :invalid_oauth_response ->
        handle_invalid_oauth_response_error(provider)

      :invalid_token_format ->
        handle_invalid_token_format_error(provider)

      :missing_token_data ->
        handle_missing_token_data_error(provider)

      :missing_access_token ->
        handle_missing_access_token_error(provider)

      :missing_expiration ->
        handle_missing_expiration_error(provider)

      _ ->
        handle_generic_oauth_error(provider)
    end
  end

  defp handle_invalid_oauth_response_error(provider) do
    ErrorResponse.new(
      "Invalid OAuth Response",
      :reauthorize,
      "The authorization response from #{provider || "the provider"} is invalid. This may be a temporary provider issue."
    )
  end

  defp handle_invalid_token_format_error(provider) do
    ErrorResponse.new(
      "Invalid Token Format",
      :reauthorize,
      "The OAuth token received from #{provider || "the provider"} is in an invalid format. Please try authorizing again."
    )
  end

  defp handle_missing_token_data_error(provider) do
    ErrorResponse.new(
      "Authorization Required",
      :reauthorize,
      "Please complete the OAuth authorization process with #{provider || "your provider"}."
    )
  end

  defp handle_missing_access_token_error(provider) do
    ErrorResponse.new(
      "Missing Access Token",
      :reauthorize,
      "The authorization response from #{provider || "the provider"} is missing the required access token."
    )
  end

  defp handle_missing_expiration_error(provider) do
    ErrorResponse.new(
      "Invalid Token Response",
      :reauthorize,
      "The OAuth token from #{provider || "the provider"} is missing expiration information."
    )
  end

  defp handle_generic_oauth_error(provider) do
    ErrorResponse.new(
      "OAuth Error",
      :generic,
      build_generic_message(provider)
    )
  end

  @spec handle_missing_scopes_error(map() | nil, provider()) :: ErrorResponse.t()
  defp handle_missing_scopes_error(error_details, provider) do
    missing_scopes = get_in(error_details, [:missing_scopes]) || []
    missing_count = length(missing_scopes)

    case missing_count do
      0 ->
        ErrorResponse.new(
          "Missing Required Permissions",
          :reauthorize,
          "Some required permissions were not granted. Please ensure you grant all selected permissions when authorizing with #{provider || "your provider"}."
        )

      1 ->
        scope = List.first(missing_scopes)

        ErrorResponse.new(
          "Missing Required Permission",
          :reauthorize,
          "The '#{scope}' permission was not granted. Please ensure you select this permission when authorizing with #{provider || "your provider"}."
        )

      _ ->
        scope_list = Enum.join(missing_scopes, "', '")

        ErrorResponse.new(
          "Missing Required Permissions",
          :reauthorize,
          "The following permissions were not granted: '#{scope_list}'. Please ensure you select all required permissions when authorizing with #{provider || "your provider"}."
        )
    end
  end

  @spec handle_missing_refresh_token_error(map() | nil, provider()) ::
          ErrorResponse.t()
  defp handle_missing_refresh_token_error(error_details, provider) do
    existing_available =
      get_in(error_details, [:existing_token_available]) || false

    if existing_available do
      ErrorResponse.new(
        "Missing Refresh Token",
        :use_existing,
        "We didn't receive a refresh token from #{provider || "this provider"}. You may have already granted access to OpenFn via another credential. If you have another credential, please use that one."
      )
    else
      ErrorResponse.new(
        "Missing Refresh Token",
        :reauthorize,
        "Please reauthorize to provide OpenFn with the necessary refresh token for #{provider || "your provider"}."
      )
    end
  end

  @spec build_generic_message(provider()) :: String.t()
  defp build_generic_message(provider) do
    "Please try authorizing with #{provider || "your provider"} again. If the problem persists, contact support."
  end

  @spec determine_action_button(map(), atom()) :: ActionButton.t()
  defp determine_action_button(assigns, suggested_action) do
    case suggested_action do
      action when action in [:reauthorize, :generic] ->
        if assigns[:revocation_endpoint] do
          create_reauth_action(assigns.myself, "Reauthorize")
        else
          create_auth_action(assigns.myself, "Authorize")
        end

      :use_existing ->
        ActionButton.new(
          "cancel-button",
          "Use Existing Credential",
          assigns.myself,
          "cancel_click"
        )
    end
  end
end
