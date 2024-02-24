defmodule LightningWeb.CredentialLive.OauthComponent do
  @moduledoc ""
  use LightningWeb, :live_component

  import LightningWeb.OauthCredentialHelper

  alias Lightning.AuthProviders.Common
  alias Lightning.Credentials

  require Logger

  attr :form, :map, required: true
  attr :id, :string, required: true
  attr :parent_id, :string, required: true
  attr :update_body, :any, required: true
  attr :action, :any, required: true
  attr :scopes_changed, :boolean, default: false
  attr :schema, :string, required: true
  attr :sandbox_value, :boolean, default: false
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
           action: @action,
           scopes_changed: @scopes_changed,
           token_body_changeset: @token_body_changeset,
           update_body: @update_body,
           sandbox_value: @sandbox_value,
           schema: @schema,
           id: "inner-form-#{@id}",
           parent_id: @parent_id
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
          <%= @provider %> authorization has not been set up on this instance.
        </span>
      </div>
    </div>
    """
  end

  def render(assigns) do
    display_reauthorize_banner =
      assigns.scopes_changed &&
        (assigns.authorization_status === :success ||
           (assigns.authorization_status === nil && assigns.action === :edit))

    display_authorize_button =
      assigns.action === :new and assigns.authorization_status === nil

    display_userinfo_loader =
      assigns.authorization_status === :pending && !display_reauthorize_banner

    display_userinfo =
      assigns.authorization_status === :success && !display_reauthorize_banner

    display_error = assigns.authorization_status === :error

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
      |> assign(display_reauthorize_banner: display_reauthorize_banner)
      |> assign(display_authorize_button: display_authorize_button)
      |> assign(display_userinfo_loader: display_userinfo_loader)
      |> assign(display_userinfo: display_userinfo)
      |> assign(display_error: display_error)

    ~H"""
    <fieldset id={@id}>
      <div :for={
        body_form <- Phoenix.HTML.FormData.to_form(:credential, @form, :body, [])
      }>
        <%= Phoenix.HTML.Form.hidden_input(body_form, :access_token) %>
        <%= Phoenix.HTML.Form.hidden_input(body_form, :refresh_token) %>
        <%= Phoenix.HTML.Form.hidden_input(body_form, :expires_at) %>
        <%= Phoenix.HTML.Form.hidden_input(body_form, :scope) %>
        <%= Phoenix.HTML.Form.hidden_input(body_form, :sandbox) %>
        <%= Phoenix.HTML.Form.hidden_input(body_form, :instance_url) %>
      </div>
      <.reauthorize_banner
        :if={@display_reauthorize_banner}
        authorize_url={@authorize_url}
        myself={@myself}
      />
      <.authorize_button
        :if={@display_authorize_button}
        authorize_url={@authorize_url}
        socket={@socket}
        myself={@myself}
        provider={@provider}
      />
      <.userinfo_loader :if={@display_userinfo_loader} provider={@provider} />
      <.userinfo
        :if={@display_userinfo}
        myself={@myself}
        userinfo={@userinfo}
        authorize_url={@authorize_url}
      />
      <.error_block
        :if={@display_error}
        type={@authorization_error}
        myself={@myself}
        provider={@provider}
        authorize_url={@authorize_url}
      />
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
              "/images/#{String.downcase(@provider)}.png"
            )
          }
          alt="Authorizing..."
          class="w-10 h-10 bg-white rounded"
        />
      </div>
      <span class="text-xl">Sign in with <%= @provider %></span>
    </.link>
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
          <svg
            class="h-5 w-5 text-blue-400"
            viewBox="0 0 20 20"
            fill="currentColor"
            aria-hidden="true"
          >
            <path
              fill-rule="evenodd"
              d="M18 10a8 8 0 11-16 0 8 8 0 0116 0zm-7-4a1 1 0 11-2 0 1 1 0 012 0zM9 9a.75.75 0 000 1.5h.253a.25.25 0 01.244.304l-.459 2.066A1.75 1.75 0 0010.747 15H11a.75.75 0 000-1.5h-.253a.25.25 0 01-.244-.304l.459-2.066A1.75 1.75 0 009.253 9H9z"
              clip-rule="evenodd"
            />
          </svg>
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

  def userinfo_loader(assigns) do
    ~H"""
    <div id="userinfo_loader" class="mt-5">
      <.text_ping_loader>
        Authenticating with <%= @provider %>
      </.text_ping_loader>
    </div>
    """
  end

  def error_block(%{type: :token_failed} = assigns) do
    ~H"""
    <div class="rounded-md bg-yellow-50 border border-yellow-200 p-4">
      <div class="flex">
        <div class="flex-shrink-0">
          <svg
            class="h-5 w-5 text-yellow-400"
            viewBox="0 0 20 20"
            fill="currentColor"
            aria-hidden="true"
          >
            <path
              fill-rule="evenodd"
              d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 5a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 5zm0 9a1 1 0 100-2 1 1 0 000 2z"
              clip-rule="evenodd"
            />
          </svg>
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-yellow-800">Something went wrong.</h3>
          <div class="mt-2 text-sm text-yellow-700">
            <p class="text-sm mt-2">
              Failed retrieving the token from the provider
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
          <svg
            class="h-5 w-5 text-yellow-400"
            viewBox="0 0 20 20"
            fill="currentColor"
            aria-hidden="true"
          >
            <path
              fill-rule="evenodd"
              d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 5a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 5zm0 9a1 1 0 100-2 1 1 0 000 2z"
              clip-rule="evenodd"
            />
          </svg>
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-yellow-800">Something went wrong.</h3>
          <div class="mt-2 text-sm text-yellow-700">
            <p class="text-sm mt-2">
              Failed renewing your access token. Please try again
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
            <p class="text-sm mt-2"></p>
            <.helpblock provider={@provider} type={@type} />
          </div>
        </div>
      </div>
    </div>
    """
  end

  def error_block(%{type: :userinfo_failed} = assigns) do
    ~H"""
    <div class="rounded-md bg-yellow-50 border border-yellow-200 p-4">
      <div class="flex">
        <div class="flex-shrink-0">
          <svg
            class="h-5 w-5 text-yellow-400"
            viewBox="0 0 20 20"
            fill="currentColor"
            aria-hidden="true"
          >
            <path
              fill-rule="evenodd"
              d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 5a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 5zm0 9a1 1 0 100-2 1 1 0 000 2z"
              clip-rule="evenodd"
            />
          </svg>
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-yellow-800">Something went wrong.</h3>
          <div class="mt-2 text-sm text-yellow-700">
            <p class="text-sm mt-2">
              Failed retrieving your information. Please
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
      </div>
    </div>
    """
  end

  def error_block(%{type: :no_refresh_token} = assigns) do
    ~H"""
    <div class="rounded-md bg-yellow-50 border border-yellow-200 p-4">
      <div class="flex">
        <div class="flex-shrink-0">
          <svg
            class="h-5 w-5 text-yellow-400"
            viewBox="0 0 20 20"
            fill="currentColor"
            aria-hidden="true"
          >
            <path
              fill-rule="evenodd"
              d="M8.485 2.495c.673-1.167 2.357-1.167 3.03 0l6.28 10.875c.673 1.167-.17 2.625-1.516 2.625H3.72c-1.347 0-2.189-1.458-1.515-2.625L8.485 2.495zM10 5a.75.75 0 01.75.75v3.5a.75.75 0 01-1.5 0v-3.5A.75.75 0 0110 5zm0 9a1 1 0 100-2 1 1 0 000 2z"
              clip-rule="evenodd"
            />
          </svg>
        </div>
        <div class="ml-3">
          <h3 class="text-sm font-medium text-yellow-800">Something went wrong.</h3>
          <div class="mt-2 text-sm text-yellow-700">
            <p class="text-sm mt-2">
              The token is missing it's
              <code class="bg-gray-200 rounded-md p-1">refresh_token</code>
              value. Please reauthorize <.link
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
            <.helpblock provider={@provider} type={@type} />
          </div>
        </div>
      </div>
    </div>
    """
  end

  def helpblock(
        %{provider: "Google", type: :userinfo_failed} =
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
        %{provider: "Google", type: :no_refresh_token} =
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
        %{provider: "Google", type: :refresh_failed} =
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
        %{provider: "Salesforce", type: :userinfo_failed} =
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
        %{provider: "Salesforce", type: :no_refresh_token} =
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
        %{provider: "Salesforce", type: :refresh_failed} =
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
    <div class="flex flex-wrap items-center justify-between sm:flex-nowrap mt-5">
      <div class="flex items-center">
        <img
          src={@userinfo["picture"]}
          class="h-14 w-14 rounded-full"
          alt={@userinfo["name"]}
        />
        <div class="ml-4">
          <h3 class="text-base font-semibold leading-6 text-gray-900">
            <%= @userinfo["name"] %>
          </h3>
          <p class="text-sm text-gray-500">
            <a href="#"><%= @userinfo["email"] %></a>
          </p>
          <div class="text-sm mt-1">
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
      </div>
    </div>
    """
  end

  @impl true
  def mount(socket) do
    subscribe(socket.id)

    {:ok, reset_assigns(socket)}
  end

  @impl true
  def update(
        %{
          form: _form,
          id: _id,
          parent_id: _parent_id,
          action: _action,
          scopes_changed: _scopes_changed,
          sandbox_value: _sandbox_value,
          token_body_changeset: _changeset,
          update_body: _body,
          schema: _schema
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
    if socket.assigns.authorization_status !== :success do
      handle_code_update(code, socket)
    else
      {:ok, socket}
    end
  end

  def update(%{error: error}, socket) do
    {:ok,
     socket |> assign(authorization_error: error, authorization_status: :error)}
  end

  def update(%{userinfo: userinfo}, socket) do
    send_update(LightningWeb.CredentialLive.FormComponent,
      id: socket.assigns.parent_id,
      authorization_status: :success
    )

    {:ok, socket |> assign(userinfo: userinfo, authorization_status: :success)}
  end

  def update(%{scopes: scopes}, socket) do
    handle_scopes_update(scopes, socket)
  end

  def update(%{sandbox: sandbox}, socket) do
    wellknown_url = socket.assigns.adapter.wellknown_url(sandbox)

    {:ok, client} = build_client(socket, wellknown_url)
    state = build_state(socket.id, __MODULE__, socket.assigns.id)

    authorize_url =
      socket.assigns.adapter.authorize_url(client, state, socket.assigns.scopes)

    {:ok,
     socket
     |> assign(sandbox: sandbox, client: client, authorize_url: authorize_url)}
  end

  defp reset_assigns(socket) do
    socket
    |> assign_new(:userinfo, fn -> nil end)
    |> assign_new(:authorization_error, fn -> nil end)
    |> assign_new(:authorization_status, fn -> nil end)
    |> assign_new(:sandbox, fn -> false end)
    |> assign_new(:scopes, fn -> [] end)
  end

  defp update_assigns(
         socket,
         %{
           form: form,
           id: id,
           parent_id: parent_id,
           action: action,
           scopes_changed: scopes_changed,
           sandbox_value: sandbox_value,
           token_body_changeset: token_body_changeset,
           update_body: update_body,
           schema: schema
         },
         token
       ) do
    adapter = Credentials.lookup_adapter(schema)

    socket
    |> assign(
      form: form,
      id: id,
      parent_id: parent_id,
      token_body_changeset: token_body_changeset,
      token: token,
      update_body: update_body,
      adapter: adapter,
      sandbox: sandbox_value,
      provider: adapter.provider_name,
      action: action,
      scopes_changed: scopes_changed
    )
  end

  defp update_client(socket) do
    wellknown_url =
      socket.assigns.adapter.wellknown_url(socket.assigns.sandbox)

    socket
    |> assign_new(:client, fn %{token: token} ->
      socket
      |> build_client(wellknown_url)
      |> case do
        {:ok, client} -> client |> Map.put(:token, token)
        {:error, _} -> nil
      end
    end)
    |> assign_new(:authorize_url, fn %{client: client} ->
      if client do
        %{optional: _optional_scopes, mandatory: mandatory_scopes} =
          socket.assigns.adapter.scopes

        state = build_state(socket.id, __MODULE__, socket.assigns.id)

        socket.assigns.adapter.authorize_url(client, state, mandatory_scopes)
      end
    end)
  end

  defp handle_code_update(code, socket) do
    client = socket.assigns.client

    # NOTE: there can be _no_ refresh token if something went wrong like if the
    # previous auth didn't receive a refresh_token

    wellknown_url = socket.assigns.adapter.wellknown_url(socket.assigns.sandbox)

    case socket.assigns.adapter.get_token(client, wellknown_url, code: code) do
      {:ok, client} ->
        client.token
        |> token_to_params()
        |> maybe_add_sandbox(socket)
        |> socket.assigns.update_body.()

        send_update(LightningWeb.CredentialLive.FormComponent,
          id: socket.assigns.parent_id,
          authorization_status: :success
        )

        {:ok,
         socket
         |> assign(
           authorization_status: :success,
           scopes_changed: false,
           client: client
         )}

      {:error, %OAuth2.Response{status_code: 400, body: body} = _response} ->
        Logger.error("Failed retrieving token from provider:\n#{inspect(body)}")

        {:ok,
         socket
         |> assign(
           authorization_error: :token_failed,
           authorization_status: :error
         )}
    end
  end

  defp handle_scopes_update(scopes, socket) do
    state = build_state(socket.id, __MODULE__, socket.assigns.id)

    authorize_url =
      socket.assigns.client
      |> socket.assigns.adapter.authorize_url(state, scopes)

    {:ok,
     socket |> assign(scopes: scopes) |> assign(authorize_url: authorize_url)}
  end

  @impl true
  def handle_event("authorize_click", _, socket) do
    {:noreply, socket |> assign(authorization_status: :pending)}
  end

  def handle_event("try_userinfo_again", _, socket) do
    Logger.debug("Attempting to retrieve userinfo again...")

    pid = self()
    Task.start(fn -> get_userinfo(pid, socket) end)
    {:noreply, socket |> assign(authorization_status: :pending)}
  end

  defp maybe_fetch_userinfo(%{assigns: %{client: nil}} = socket) do
    socket
  end

  defp maybe_fetch_userinfo(socket) do
    %{token_body_changeset: token_body_changeset, token: token} = socket.assigns

    if socket |> changed?(:token) and token_body_changeset.valid? do
      pid = self()

      # TODO: We should change all those Task.start(fn) with assign_async/4 (https://hexdocs.pm/phoenix_live_view/Phoenix.LiveView.html#assign_async/4)
      if Common.still_fresh(token) do
        Logger.debug("Retrieving userinfo")
        Task.start(fn -> get_userinfo(pid, socket) end)
      else
        Logger.debug("Refreshing expired token")
        Task.start(fn -> refresh_token(pid, socket) end)
      end
    end

    socket
  end

  defp get_userinfo(pid, socket) do
    %{id: id, client: client, token: token, sandbox: sandbox, adapter: adapter} =
      socket.assigns

    wellknown_url = adapter.wellknown_url(sandbox)

    adapter.get_userinfo(client, token, wellknown_url)
    |> case do
      {:ok, resp} ->
        send_update(pid, __MODULE__, id: id, userinfo: resp.body)

      {:error, resp} ->
        Logger.error("Failed retrieving userinfo with:\n#{inspect(resp)}")

        send_update(pid, __MODULE__, id: id, error: :userinfo_failed)
    end
  end

  defp refresh_token(pid, socket) do
    %{
      id: id,
      client: client,
      update_body: update_body,
      token: token,
      sandbox: sandbox,
      adapter: adapter
    } = socket.assigns

    wellknown_url = adapter.wellknown_url(sandbox)

    adapter.refresh_token(client, token, wellknown_url)
    |> case do
      {:ok, token} ->
        update_body.(token |> token_to_params() |> maybe_add_sandbox(socket))

        Logger.debug("Retrieving userinfo")
        Task.start(fn -> get_userinfo(pid, socket) end)

      {:error, reason} ->
        Logger.error("Failed refreshing valid token: #{inspect(reason)}")

        send_update(pid, __MODULE__, id: id, error: :refresh_failed)
    end
  end

  defp build_client(socket, wellknown_url) do
    socket.assigns.adapter.build_client(
      wellknown_url,
      callback_url: LightningWeb.RouteHelpers.oidc_callback_url()
    )
  end

  defp token_to_params(%OAuth2.AccessToken{} = token) do
    base = token |> Map.from_struct()

    {extra, base} =
      if Map.has_key?(base, :other_params) do
        expires_at = Map.get(base.other_params, "expires_at", "")
        scope = Map.get(base.other_params, "scope", "")
        instance_url = Map.get(base.other_params, "instance_url", "")

        {%{expires_at: expires_at, scope: scope, instance_url: instance_url},
         Map.delete(base, :other_params)}
      else
        {%{}, base}
      end

    Map.merge(base, extra, fn
      :expires_at, v1, v2 when v1 in [nil, ""] -> v2
      :expires_at, v1, v2 when v2 in [nil, ""] -> v1
      _k, _v1, v2 -> v2
    end)
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

  defp maybe_add_sandbox(token, socket) do
    if socket.assigns.provider === "Salesforce" do
      Map.put_new(token, :sandbox, socket.assigns.sandbox)
    else
      token
    end
  end
end
