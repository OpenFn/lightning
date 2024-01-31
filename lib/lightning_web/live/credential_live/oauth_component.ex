defmodule LightningWeb.CredentialLive.OauthComponent do
  @moduledoc ""
  use LightningWeb, :live_component

  import LightningWeb.OauthCredentialHelper

  alias Lightning.AuthProviders.Common
  alias LightningWeb.CredentialLive.ScopeSelectionComponent

  require Logger

  attr :form, :map, required: true
  attr :id, :string, required: true
  attr :update_body, :any, required: true
  attr :provider, :any, required: true
  slot :inner_block

  def fieldset(assigns) do
    changeset = assigns.form.source

    parent_valid? = !(changeset.errors |> Keyword.drop([:body]) |> Enum.any?())

    token_body_changeset =
      Common.TokenBody.changeset(
        changeset |> Ecto.Changeset.get_field(:body) || %{}
      )

    assigns =
      assigns
      |> assign(
        update_body: assigns.update_body,
        valid?: parent_valid? and token_body_changeset.valid?,
        token_body_changeset: token_body_changeset
      )

    ~H"""
    <%= render_slot(
      @inner_block,
      {Phoenix.LiveView.TagEngine.component(
         &live_component/1,
         [
           module: __MODULE__,
           form: @form,
           token_body_changeset: @token_body_changeset,
           update_body: @update_body,
           provider: @provider,
           id: "#{provider_name(@provider)}-oauth-inner-form-#{@id}"
         ],
         {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
       ), @valid?}
    ) %>
    """
  end

  @impl true
  def render(%{client: nil} = assigns) do
    ~H"""
    <div id={@id} class="flex items-center place-content-center pt-2">
      <div class="text-center">
        <div class="text-base font-medium text-gray-900">
          No Client Configured
        </div>
        <span class="text-sm">
          <%= provider_name(@provider) |> String.capitalize() %> authorization has not been set up on this instance.
        </span>
      </div>
    </div>
    """
  end

  def render(assigns) do
    assigns =
      assigns
      |> update(:form, fn form, %{token_body_changeset: token_body_changeset} ->
        # Merge in any changes that have been made to the TokenBody changeset
        # _inside_ this component.
        %{
          form
          | params: Map.put(form.params, "body", token_body_changeset.params)
        }
      end)
      |> assign(
        show_authorize:
          !(assigns.authorizing || assigns.error || assigns.userinfo)
      )

    ~H"""
    <fieldset id={@id}>
      <div :for={
        body_form <- Phoenix.HTML.FormData.to_form(:credential, @form, :body, [])
      }>
        <%= Phoenix.HTML.Form.hidden_input(body_form, :access_token) %>
        <%= Phoenix.HTML.Form.hidden_input(body_form, :refresh_token) %>
        <%= Phoenix.HTML.Form.hidden_input(body_form, :expires_at) %>
        <%= Phoenix.HTML.Form.hidden_input(body_form, :scope) %>
      </div>

      <%= if @provider === Lightning.AuthProviders.Salesforce do %>
        <.live_component
          id={"#{@id}-scope-selection"}
          parent_id={@id}
          module={ScopeSelectionComponent}
        />
      <% end %>

      <div class="lg:grid lg:grid-cols-2 grid-cols-1 grid-flow-col mt-5">
        <.authorize_button
          :if={@show_authorize}
          authorize_url={@authorize_url}
          socket={@socket}
          myself={@myself}
          provider={@provider}
        />
        <.disabled_authorize_button
          :if={!@show_authorize}
          authorize_url={@authorize_url}
          socket={@socket}
          myself={@myself}
          provider={@provider}
        />

        <.error_block
          :if={@error}
          type={@error}
          myself={@myself}
          provider={@provider}
        />
        <.userinfo :if={@userinfo} userinfo={@userinfo} />
      </div>
    </fieldset>
    """
  end

  def authorize_button(assigns) do
    ~H"""
    <.link
      href={@authorize_url}
      id="authorize-button"
      target="_blank"
      class="bg-primary-600 hover:bg-primary-700 text-white font-bold py-1 px-1 pr-3 rounded inline-flex items-center"
      phx-click="authorize_click"
      phx-target={@myself}
    >
      <div class="py-1 px-1 mr-2 bg-white rounded">
        <img
          src={
            Routes.static_path(
              @socket,
              "/images/#{provider_name(@provider)}.png"
            )
          }
          alt="Authorizing..."
          class="w-10 h-10 bg-white rounded"
        />
      </div>
      <span class="text-xl">Sign in with <%= provider_name(@provider) %></span>
    </.link>
    """
  end

  def disabled_authorize_button(assigns) do
    ~H"""
    <div>
      <div class="bg-primary-300 text-white font-bold py-1 px-1 pr-3 rounded inline-flex items-center">
        <div class="py-1 px-1 mr-2 bg-white rounded">
          <img
            src={
              Routes.static_path(
                @socket,
                "/images/#{provider_name(@provider)}.png"
              )
            }
            alt="Authorizing..."
            class="w-10 h-10 bg-white rounded"
          />
        </div>
        <span class="text-xl">
          Sign in with <%= provider_name(@provider) |> String.capitalize() %>
        </span>
      </div>
      <div class="text-sm ml-1">
        Not working?
        <.link
          href={@authorize_url}
          target="_blank"
          phx-target={@myself}
          phx-click="authorize_click"
          class="hover:underline text-primary-900"
        >
          Reauthorize.
        </.link>
      </div>
    </div>
    """
  end

  def error_block(%{type: :userinfo_failed} = assigns) do
    ~H"""
    <div class="mx-auto pt-2 max-w-md">
      <div class="text-center">
        <Heroicons.exclamation_triangle class="h-6 w-6 text-red-600 inline-block" />
        <div class="text-base font-medium text-gray-900">
          Something went wrong.
        </div>
        <p class="text-sm mt-2">
          Failed retrieving your information.
        </p>
        <p class="text-sm mt-2">
          Please
          <a
            href="#"
            phx-click="try_userinfo_again"
            phx-target={@myself}
            class="hover:underline text-primary-900"
          >
            try again.
          </a>
        </p>
        <.helpblock provider={@provider} type={@type} />
      </div>
    </div>
    """
  end

  def error_block(%{type: :no_refresh_token} = assigns) do
    ~H"""
    <div class="mx-auto pt-2 max-w-md">
      <div class="text-center">
        <Heroicons.exclamation_triangle class="h-6 w-6 text-red-600 inline-block" />
        <div class="text-base font-medium text-gray-900">
          Something went wrong.
        </div>
        <p class="text-sm mt-2">
          The token is missing it's
          <code class="bg-gray-200 rounded-md p-1">refresh_token</code>
          value.
        </p>
        <p class="text-sm mt-2">
          Please reauthorize.
        </p>
        <.helpblock provider={@provider} type={@type} />
      </div>
    </div>
    """
  end

  def error_block(%{type: :refresh_failed} = assigns) do
    ~H"""
    <div class="mx-auto pt-2 max-w-md">
      <div class="text-center">
        <Heroicons.exclamation_triangle class="h-6 w-6 text-red-600 inline-block" />
        <div class="text-base font-medium text-gray-900">
          Something went wrong.
        </div>
        <p class="text-sm mt-2">
          Failed renewing your access token.
        </p>
        <p class="text-sm mt-2">
          Please try again.
        </p>
        <.helpblock provider={@provider} type={@type} />
      </div>
    </div>
    """
  end

  def helpblock(
        %{provider: Lightning.AuthProviders.Google, type: :userinfo_failed} =
          assigns
      ) do
    ~H"""
    <p class="text-sm mt-2">
      If the issue persists, please follow the "Remove third-party account access"
      instructions on the
      <a
        class="text-indigo-600 underline"
        href="https://support.google.com/accounts/answer/3466521"
        target="_blank"
      >
        Manage third-party apps & services with access to your account
      </a>
      <Heroicons.arrow_top_right_on_square class="h-4 w-4 text-indigo-600 inline-block" />
      page.
    </p>
    """
  end

  def helpblock(
        %{provider: Lightning.AuthProviders.Google, type: :no_refresh_token} =
          assigns
      ) do
    ~H"""
    <p class="text-sm mt-2">
      If the issue persists, please follow the "Remove third-party account access"
      instructions on the
      <a
        class="text-indigo-600 underline"
        href="https://support.google.com/accounts/answer/3466521"
        target="_blank"
      >
        Manage third-party apps & services with access to your account
      </a>
      <Heroicons.arrow_top_right_on_square class="h-4 w-4 text-indigo-600 inline-block" />
      page.
    </p>
    """
  end

  def helpblock(
        %{provider: Lightning.AuthProviders.Google, type: :refresh_failed} =
          assigns
      ) do
    ~H"""
    <p class="text-sm mt-2">
      If the issue persists, please follow the "Remove third-party account access"
      instructions on the
      <a
        class="text-indigo-600 underline"
        href="https://support.google.com/accounts/answer/3466521"
        target="_blank"
      >
        Manage third-party apps & services with access to your account
      </a>
      <Heroicons.arrow_top_right_on_square class="h-4 w-4 text-indigo-600 inline-block" />
      page.
    </p>
    """
  end

  def helpblock(
        %{provider: Lightning.AuthProviders.Salesforce, type: :userinfo_failed} =
          assigns
      ) do
    ~H"""
    <p class="text-sm mt-2">
      If the issue persists, please follow the "Query for User Information"
      instructions on the
      <a
        class="text-indigo-600 underline"
        href="https://help.salesforce.com/s/articleView?id=sf.remoteaccess_authenticate.htm&type=5"
        target="_blank"
      >
        Authorize Connected Apps With OAuth
      </a>
      <Heroicons.arrow_top_right_on_square class="h-4 w-4 text-indigo-600 inline-block" />
      page.
    </p>
    """
  end

  def helpblock(
        %{provider: Lightning.AuthProviders.Salesforce, type: :no_refresh_token} =
          assigns
      ) do
    ~H"""
    <p class="text-sm mt-2">
      If the issue persists, please follow the "OAuth 2.0 Refresh Token Flow for Renewed Sessions"
      instructions on the
      <a
        class="text-indigo-600 underline"
        href="https://support.google.com/accounts/answer/3466521"
        target="_blank"
      >
        OAuth Authorization Flows
      </a>
      <Heroicons.arrow_top_right_on_square class="h-4 w-4 text-indigo-600 inline-block" />
      page.
    </p>
    """
  end

  def helpblock(
        %{provider: Lightning.AuthProviders.Salesforce, type: :refresh_failed} =
          assigns
      ) do
    ~H"""
    <p class="text-sm mt-2">
      If the issue persists, please follow the "OAuth 2.0 Refresh Token Flow for Renewed Sessions"
      instructions on the
      <a
        class="text-indigo-600 underline"
        href="https://support.google.com/accounts/answer/3466521"
        target="_blank"
      >
        OAuth Authorization Flows
      </a>
      <Heroicons.arrow_top_right_on_square class="h-4 w-4 text-indigo-600 inline-block" />
      page.
    </p>
    """
  end

  def userinfo(assigns) do
    ~H"""
    <div class="flex flex-col items-center self-center">
      <div class="flex-none">
        <img src={@userinfo["picture"]} class="h-12 w-12 rounded-full" />
      </div>
      <div class="flex mb-1 ml-2">
        <span class="font-medium text-lg text-gray-700">
          <%= @userinfo["name"] %>
        </span>
      </div>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    subscribe(socket.id)

    {:ok, socket |> assign(userinfo: nil)}
  end

  @impl true
  def update(
        %{
          form: _form,
          id: _id,
          token_body_changeset: _changeset,
          update_body: _body,
          provider: _provider
        } = params,
        socket
      ) do
    token =
      params.token_body_changeset
      |> Ecto.Changeset.apply_changes()
      |> params_to_token()

    {:ok,
     socket
     |> reset_assigns()
     |> update_assigns(params, token)
     |> update_client()
     |> maybe_fetch_userinfo()}
  end

  def update(%{code: code}, socket) do
    handle_code_update(code, socket)
  end

  def update(%{error: error}, socket) do
    {:ok, socket |> assign(error: error, authorizing: false)}
  end

  def update(%{userinfo: userinfo}, socket) do
    {:ok, socket |> assign(userinfo: userinfo, authorizing: false, error: nil)}
  end

  def update(%{scopes: scopes}, socket) do
    handle_scopes_update(scopes, socket)
  end

  defp reset_assigns(socket) do
    socket
    |> assign_new(:userinfo, fn -> nil end)
    |> assign_new(:authorizing, fn -> false end)
  end

  defp update_assigns(
         socket,
         %{
           form: form,
           id: id,
           token_body_changeset: token_body_changeset,
           update_body: update_body,
           provider: provider
         },
         token
       ) do
    socket
    |> assign(
      form: form,
      id: id,
      token_body_changeset: token_body_changeset,
      token: token,
      error: token_error(token),
      update_body: update_body,
      provider: provider
    )
  end

  defp update_client(socket) do
    socket
    |> assign_new(:client, fn %{token: token} ->
      socket
      |> build_client()
      |> case do
        {:ok, client} -> client |> Map.put(:token, token)
        {:error, _} -> nil
      end
    end)
    |> assign_new(:authorize_url, fn %{client: client} ->
      if client do
        socket.assigns.provider.authorize_url(
          client,
          build_state(socket.id, __MODULE__, socket.assigns.id),
          []
        )
      end
    end)
  end

  defp handle_code_update(code, socket) do
    client = socket.assigns.client

    # NOTE: there can be _no_ refresh token if something went wrong like if the
    # previous auth didn't receive a refresh_token

    {:ok, client} = socket.assigns.provider.get_token(client, code: code)

    client.token
    |> token_to_params()
    |> socket.assigns.update_body.()

    {:ok, socket |> assign(authorizing: false, client: client)}
  end

  defp handle_scopes_update(scopes, socket) do
    authorize_url =
      socket.assigns.provider.authorize_url(
        socket.assigns.client,
        build_state(socket.id, __MODULE__, socket.assigns.id),
        scopes
      )

    {:ok, socket |> assign(authorize_url: authorize_url)}
  end

  @impl true
  def handle_event("authorize_click", _, socket) do
    {:noreply, socket |> assign(authorizing: true, userinfo: nil, error: nil)}
  end

  def handle_event("try_userinfo_again", _, socket) do
    Logger.debug("Attempting to retrieve userinfo again...")

    pid = self()
    Task.start(fn -> get_userinfo(pid, socket) end)
    {:noreply, socket |> assign(authorizing: true, error: nil, userinfo: nil)}
  end

  defp maybe_fetch_userinfo(%{assigns: %{client: nil}} = socket) do
    socket
  end

  defp maybe_fetch_userinfo(socket) do
    %{token_body_changeset: token_body_changeset, token: token} = socket.assigns

    if socket |> changed?(:token) and token_body_changeset.valid? do
      pid = self()

      if OAuth2.AccessToken.expired?(token) do
        Logger.debug("Refreshing expired token")

        Task.start(fn -> refresh_token(pid, socket) end)
      else
        Logger.debug("Retrieving userinfo")

        Task.start(fn -> get_userinfo(pid, socket) end)
      end

      socket |> assign(authorizing: true)
    else
      socket
    end
  end

  defp get_userinfo(pid, socket) do
    %{id: id, client: client, token: token} = socket.assigns

    socket.assigns.provider.get_userinfo(client, token)
    |> case do
      {:ok, resp} ->
        send_update(pid, __MODULE__, id: id, userinfo: resp.body)

      {:error, resp} ->
        Logger.error("Failed retrieving userinfo with:\n#{inspect(resp)}")

        send_update(pid, __MODULE__, id: id, error: :userinfo_failed)
    end
  end

  defp refresh_token(pid, socket) do
    %{id: id, client: client, update_body: update_body, token: token} =
      socket.assigns

    socket.assigns.provider.refresh_token(client, token)
    |> case do
      {:ok, token} ->
        update_body.(token |> token_to_params())

      {:error, reason} ->
        Logger.error("Failed refreshing valid token: #{inspect(reason)}")

        send_update(pid, __MODULE__, id: id, error: :refresh_failed)
    end
  end

  defp build_client(socket) do
    socket.assigns.provider.build_client(
      callback_url: LightningWeb.RouteHelpers.oidc_callback_url()
    )
  end

  defp token_to_params(%OAuth2.AccessToken{} = token) do
    token
    |> Map.from_struct()
    |> Enum.reduce([], fn {k, v}, acc ->
      case k do
        _ when k in [:access_token, :refresh_token, :scope, :expires_at] ->
          [{k |> to_string(), v} | acc]

        :other_params ->
          Enum.concat(Map.to_list(v), acc)

        _ ->
          acc
      end
    end)
    |> Map.new()
  end

  defp params_to_token(%Lightning.AuthProviders.Common.TokenBody{} = token) do
    struct!(
      OAuth2.AccessToken,
      token
      |> Map.from_struct()
      |> Map.filter(fn {k, _v} ->
        k in [:access_token, :refresh_token, :expires_at]
      end)
    )
  end

  defp token_error(token) do
    if is_nil(token.refresh_token) and token.access_token do
      :no_refresh_token
    else
      nil
    end
  end

  defp provider_name(Lightning.AuthProviders.Salesforce) do
    "salesforce"
  end

  defp provider_name(Lightning.AuthProviders.Google) do
    "google"
  end
end
