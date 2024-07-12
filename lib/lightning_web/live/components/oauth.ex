defmodule LightningWeb.Components.Oauth do
  @moduledoc false
  use LightningWeb, :component

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
          <div class="text-sm mt-2">
            Success. If your credential stops working, you may try to
            <.link
              href={@authorize_url}
              target="_blank"
              phx-target={@myself}
              phx-click="authorize_click"
              class="hover:underline text-primary-900"
            >
              re-authorize.
            </.link>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def error_block(%{type: :token_failed} = assigns) do
    ~H"""
    <div class="rounded-md bg-yellow-50 border border-yellow-200 p-4">
      <div class="flex">
        <div class="flex-shrink-0">
          <Heroicons.exclamation_triangle class="h-5 w-5 text-yellow-400" />
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-yellow-800">Something went wrong.</h3>
          <div class="mt-2 text-sm text-yellow-700">
            <p class="text-sm mt-2">
              Failed retrieving the token from the provider. Please try again
              <.link
                href={@authorize_url}
                target="_blank"
                phx-target={@myself}
                phx-click="authorize_click"
                class="hover:underline text-primary-900"
              >
                here
                <Heroicons.arrow_top_right_on_square class="h-4 w-4 text-indigo-600 inline-block" />.
              </.link>
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def error_block(%{type: :refresh_failed} = assigns) do
    ~H"""
    <div class="rounded-md bg-yellow-50 border border-yellow-200 p-4">
      <div class="flex">
        <div class="flex-shrink-0">
          <Heroicons.exclamation_triangle class="h-5 w-5 text-yellow-400" />
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-yellow-800">Something went wrong.</h3>
          <div class="mt-2 text-sm text-yellow-700">
            <p class="text-sm mt-2">
              Failed renewing your access token. Please request a new token by clicking
              <.link
                href={@authorize_url}
                target="_blank"
                phx-target={@myself}
                phx-click="authorize_click"
                class="hover:underline text-primary-900"
              >
                here
                <Heroicons.arrow_top_right_on_square class="h-4 w-4 text-indigo-600 inline-block" />.
              </.link>
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def error_block(%{type: :userinfo_failed} = assigns) do
    ~H"""
    <div class="rounded-md bg-blue-50 p-4">
      <div class="flex">
        <div class="flex-shrink-0">
          <Heroicons.exclamation_triangle class="h-5 w-5 text-blue-400" />
        </div>
        <div class="ml-3 flex-1 md:flex md:justify-between">
          <p class="text-sm text-blue-700">
            That seemed to work, but we couldn't fetch your user information. You can save your credential now or try again.
          </p>
          <p class="mt-3 text-sm md:ml-6 md:mt-0">
            <a
              href="#"
              class="whitespace-nowrap font-medium text-blue-700 hover:text-blue-600"
              phx-click="try_userinfo_again"
              phx-target={@myself}
            >
              Try again <span aria-hidden="true"> &rarr;</span>
            </a>
          </p>
        </div>
      </div>
    </div>
    """
  end

  def error_block(%{type: :no_refresh_token} = assigns) do
    ~H"""
    <div class="rounded-md bg-yellow-50 border border-yellow-200 p-4">
      <div class="flex">
        <div class="flex-shrink-0">
          <Heroicons.exclamation_triangle class="h-5 w-5 text-yellow-400" />
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-yellow-800">Missing refresh token</h3>
          <div class="mt-2 text-sm text-yellow-700">
            <p class="text-sm mt-2">
              We didn't receive a refresh token from this provider. Sometimes this happens if you have already granted access to OpenFn via another credential. If you have another credential, please use that one. If you don't, please revoke OpenFn's access to your provider via the "third party apps" section of their website. Once that is done, you can try to reauthorize
              <.link
                href={@authorize_url}
                target="_blank"
                phx-target={@myself}
                phx-click="authorize_click"
                class="hover:underline text-primary-900"
              >
                here
                <Heroicons.arrow_top_right_on_square class="h-4 w-4 text-indigo-600 inline-block" />.
              </.link>
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def error_block(%{type: :code_failed} = assigns) do
    ~H"""
    <div class="rounded-md bg-yellow-50 border border-yellow-200 p-4">
      <div class="flex">
        <div class="flex-shrink-0">
          <Heroicons.exclamation_triangle class="h-5 w-5 text-yellow-400" />
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-yellow-800">Something went wrong.</h3>
          <div class="mt-2 text-sm text-yellow-700">
            <p class="text-sm mt-2">
              Failed retrieving authentication code. Please reauthorize <.link
                href={@authorize_url}
                target="_blank"
                phx-target={@myself}
                phx-click="authorize_click"
                class="hover:underline text-primary-900"
              >
            here
            <Heroicons.arrow_top_right_on_square class="h-4 w-4 text-indigo-600 inline-block" />.
          </.link>.
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def missing_client_warning(assigns) do
    ~H"""
    <div class="rounded-md bg-red-50 p-4 mb-4">
      <div class="flex">
        <div class="flex-shrink-0">
          <Heroicons.exclamation_triangle class="h-5 w-5 text-red-400" />
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-red-800">OAuth client not found.</h3>
          <div class="mt-2 text-sm text-red-700">
            <p>
              The associated Oauth client for this credential cannot be found. Create a new client or contact your administrator.
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  def reauthorize_banner(assigns) do
    ~H"""
    <div
      id="re-authorize-banner"
      class="rounded-md bg-blue-50 border border-blue-100 p-2 mt-5"
    >
      <div class="flex">
        <div class="flex-shrink-0">
          <Heroicons.information_circle class="h-5 w-5 text-blue-400" />
        </div>
        <div class="ml-3 flex-1 md:flex md:justify-between">
          <p class="text-sm text-slate-700">
            Please re-authenticate to save your credential with the updated scopes
          </p>
          <p class="mt-3 text-sm md:ml-6 md:mt-0">
            <.link
              href={@authorize_url}
              id="re-authorize-button"
              target="_blank"
              class="whitespace-nowrap font-medium text-blue-700 hover:text-blue-600"
              phx-click="authorize_click"
              phx-target={@myself}
            >
              Re-authenticate <span aria-hidden="true"> &rarr;</span>
            </.link>
          </p>
        </div>
      </div>
    </div>
    """
  end
end
