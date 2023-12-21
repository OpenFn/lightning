defmodule LightningWeb.CredentialLive.GoogleSheetsComponent do
  @moduledoc """
  Form component to setup a Google Sheets component.

  This component has several moving parts:

  - Subscribes to a PubSub topic specially link to the component id
    See: `LightningWeb.OauthCredentialHelper`.
  - Uses the `Lightning.Google` module to set up an OAuth client for generating
    urls, exchanging the code and requesting a new `access_token`.

  The flow for creating a new token is:

  - Generate an authorization link which contains:
    - The authorization url from the Google client with the applications callback_url
    - A state string that is an encrypted set of data with the components module and
      id in it
  - Once the user authorizes the client the callback is requested with a code
  - The `LightningWeb.OidcController` decodes the state returned to it and does
    a 'broadcast_forward' which is simply a message expected to be received by a
    LiveView and applied to `Phoenix.LiveView.send_update/3`.
  - The component receives the code and requests a token.
  - Any changes to the token (Credential body) are still handled by the parent
    component and so a `update_body` function is passed in to send params changes
    back up to update the form.
  """
  use LightningWeb, :live_component
  require Logger

  alias Lightning.AuthProviders.Google
  import LightningWeb.OauthCredentialHelper

  attr :form, :map, required: true
  attr :update_body, :any, required: true
  slot :inner_block

  def fieldset(assigns) do
    changeset = assigns.form.source

    parent_valid? = !(changeset.errors |> Keyword.drop([:body]) |> Enum.any?())

    token_body_changeset =
      Google.TokenBody.changeset(
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
           id: "google-sheets-inner-form-#{@id}"
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
          Google Authorization has not been set up on this instance.
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
      <div class="lg:grid lg:grid-cols-2 grid-cols-1 grid-flow-col">
        <.authorize_button
          :if={@show_authorize}
          authorize_url={@authorize_url}
          socket={@socket}
          myself={@myself}
        />
        <.disabled_authorize_button
          :if={!@show_authorize}
          authorize_url={@authorize_url}
          socket={@socket}
          myself={@myself}
        />

        <.error_block :if={@error} type={@error} myself={@myself} />
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
      class="google-authorize group disabled"
      phx-click="authorize_click"
      phx-target={@myself}
    >
      <img
        src={
          Routes.static_path(
            @socket,
            "/images/btn_google_signin_dark_normal_web@2x.png"
          )
        }
        alt="Authorize with Google"
        class="group-hover:hidden"
      />
      <img
        src={
          Routes.static_path(
            @socket,
            "/images/btn_google_signin_dark_pressed_web@2x.png"
          )
        }
        alt="Authorize with Google"
        class="hidden group-hover:block"
      />
    </.link>
    """
  end

  def disabled_authorize_button(assigns) do
    ~H"""
    <div class="mx-auto">
      <img
        src={
          Routes.static_path(
            @socket,
            "/images/btn_google_signin_dark_disabled_web@2x.png"
          )
        }
        alt="Authorizing..."
        class="mx-auto"
      />
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
      </div>
    </div>
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
          form: form,
          id: id,
          token_body_changeset: token_body_changeset,
          update_body: update_body
        },
        socket
      ) do
    token =
      params_to_token(
        token_body_changeset
        |> Ecto.Changeset.apply_changes()
      )

    socket =
      socket
      |> assign_new(:userinfo, fn -> nil end)
      |> assign_new(:authorizing, fn -> false end)
      |> assign(
        form: form,
        id: id,
        token_body_changeset: token_body_changeset,
        token: token,
        error: token_error(token),
        update_body: update_body
      )
      |> assign_new(:client, fn %{token: token} ->
        case build_client() do
          {:ok, client} -> client |> Map.put(:token, token)
          {:error, _} -> nil
        end
      end)
      |> assign_new(:authorize_url, fn %{client: client} ->
        if client do
          Google.authorize_url(client, build_state(socket.id, __MODULE__, id))
        end
      end)
      |> maybe_fetch_userinfo()

    {:ok, socket}
  end

  @impl true
  def update(%{code: code}, socket) do
    client = socket.assigns.client

    # NOTE: there can be _no_ refresh token if something went wrong like if the
    # previous auth didn't receive a refresh_token

    {:ok, client} = Google.get_token(client, code: code)

    socket.assigns.update_body.(client.token |> token_to_params())

    {:ok, socket |> assign(authorizing: false, client: client)}
  end

  def update(%{error: error}, socket) do
    {:ok, socket |> assign(error: error, authorizing: false)}
  end

  def update(%{userinfo: userinfo}, socket) do
    {:ok, socket |> assign(userinfo: userinfo, authorizing: false, error: nil)}
  end

  @impl true
  def handle_event("authorize_click", _, socket) do
    {:noreply, socket |> assign(authorizing: true, userinfo: nil, error: nil)}
  end

  @impl true
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

    Google.get_userinfo(client, token)
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

    Google.refresh_token(client, token)
    |> case do
      {:ok, token} ->
        update_body.(token |> token_to_params())

      {:error, reason} ->
        Logger.error("Failed refreshing valid token: #{inspect(reason)}")

        send_update(pid, __MODULE__, id: id, error: :refresh_failed)
    end
  end

  defp build_client() do
    Google.build_client(
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

  defp params_to_token(%Google.TokenBody{} = token) do
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
end
