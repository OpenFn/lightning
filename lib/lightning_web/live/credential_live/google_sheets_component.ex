defmodule LightningWeb.CredentialLive.GoogleSheetsComponent do
  use LightningWeb, :live_component

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
        token_body_changeset: token_body_changeset,
        valid?: parent_valid? and token_body_changeset.valid?
      )

    ~H"""
    <%= render_slot(
      @inner_block,
      {Phoenix.LiveView.HTMLEngine.component(
         &live_component/1,
         [
           module: __MODULE__,
           form: @form,
           update_body: @update_body,
           token_body_changeset: @token_body_changeset,
           id: "google-sheets-inner-form"
         ],
         {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
       ), @valid?}
    ) %>
    """
  end

  @impl true
  def render(assigns) do
    assigns =
      assigns
      |> update(:form, fn form, %{token_body_changeset: token_body_changeset} ->
        # Merge in any changes that have been make to the TokenBody changeset
        # _inside_ this component.
        %{
          form
          | params: Map.put(form.params, "body", token_body_changeset.params)
        }
      end)

    ~H"""
    <fieldset id={@id}>
      <legend class="contents text-base font-medium text-gray-900">
        Details
      </legend>
      <p class="text-sm text-gray-500">
        Configuration for this credential.
      </p>
      <div :for={
        body_form <- Phoenix.HTML.FormData.to_form(:credential, @form, :body, [])
      }>
        <%= hidden_input(body_form, :access_token) %>
        <%= hidden_input(body_form, :refresh_token) %>
        <%= hidden_input(body_form, :expires_at) %>
        <%= hidden_input(body_form, :scope) %>
      </div>
      <.authorize_button
        :if={!@authorizing}
        authorize_url={@authorize_url}
        socket={@socket}
        myself={@myself}
      />
      <.in_progress_feedback :if={!@authorizing} socket={@socket} myself={@myself} />
    </fieldset>
    """
  end

  def authorize_button(assigns) do
    ~H"""
    <.link
      href={@authorize_url}
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
        class="w-72 group-hover:hidden"
      />
      <img
        src={
          Routes.static_path(
            @socket,
            "/images/btn_google_signin_dark_pressed_web@2x.png"
          )
        }
        alt="Authorize with Google"
        class="w-72 hidden group-hover:block"
      />
    </.link>
    """
  end

  def in_progress_feedback(assigns) do
    ~H"""
    <img
      src={
        Routes.static_path(
          @socket,
          "/images/btn_google_signin_dark_disabled_web@2x.png"
        )
      }
      alt="Authorizing..."
      class="w-72"
    />
    <span class="text-sm">
      Not working?
      <.link
        href="#"
        phx-target={@myself}
        phx-click="cancel"
        class="hover:underline text-primary-900"
      >
        Try again.
      </.link>
    </span>
    """
  end

  @impl true
  def mount(socket) do
    subscribe(socket.id)

    {:ok, socket}
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
    # oauth pubsub module
    # oauth state generator

    # subscribe to oauth channel
    # handle_info should call back to this component

    # id for the channel - use the socket id

    # state
    # id for send_update - must be what was passed to the live_component
    # module for send_update
    # + the code? (i.e. we want to handle the token exchange in here)

    {:ok,
     socket
     |> assign(
       form: form,
       id: id,
       token_body_changeset: token_body_changeset,
       update_body: update_body
     )
     |> assign_new(:authorizing, fn -> false end)
     |> assign_new(:client, &build_client/0)
     |> assign_new(:authorize_url, fn %{client: client} ->
       Google.authorize_url(client, build_state(socket.id, __MODULE__, id))
     end)}
  end

  # TODO: use the introspection url to check on the token

  # NOTE: using oauth2-mock-server for development

  # TODO: error scenarios don't have a code, but have a error & state combo
  # https://www.oauth.com/oauth2-servers/authorization/the-authorization-response/

  # redirect_uri: Application.get_env(:open_fn, :oauth)[:redirect_uri],
  # code: code,
  # grant_type: "authorization_code"

  @impl true
  def update(%{code: code}, socket) do
    client = socket.assigns.client

    # NOTE: there can be _no_ refresh token if something went wrong like if the
    # previous auth didn't receive a refresh_token

    client = Google.get_token(client, code: code)

    socket.assigns.update_body.(client.token |> token_to_params())

    {:ok, socket |> assign(authorizing: false, client: client)}
  end

  @impl true
  def update(%{authorizing: authorizing}, socket) do
    {:ok, socket |> assign(authorizing: authorizing)}
  end

  @impl true
  def handle_event("authorize_click", _, socket) do
    {:noreply, socket |> assign(authorizing: true)}
  end

  @impl true
  def handle_event("cancel", _, socket) do
    {:noreply, socket |> assign(authorizing: false)}
  end

  defp build_client() do
    Google.build_client(
      callback_url: "http://localhost:4000/authenticate/callback"
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
end
