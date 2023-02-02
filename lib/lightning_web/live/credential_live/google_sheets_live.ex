defmodule LightningWeb.CredentialLive.GoogleSheetsLive do
  use LightningWeb, :live_component

  import LightningWeb.OauthCredentialHelper

  attr :form, :map, required: true
  slot :inner_block

  def fieldset(assigns) do
    changeset = assigns.form.source

    assigns = assigns |> assign(valid?: changeset.valid?)

    ~H"""
    <%= render_slot(
      @inner_block,
      {Phoenix.LiveView.HTMLEngine.component(
         &live_component/1,
         [module: __MODULE__, form: @form, id: "google-sheets-inner-form"],
         {__ENV__.module, __ENV__.function, __ENV__.file, __ENV__.line}
       ), @valid?}
    ) %>
    """
  end

  @impl true
  def render(assigns) do
    ~H"""
    <fieldset>
      <legend class="contents text-base font-medium text-gray-900">
        Details
      </legend>
      <p class="text-sm text-gray-500">
        Configuration for this credential.
      </p>
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
    # socket = socket |> assign_new(:id, fn -> Ecto.UUID.generate() end)

    subscribe(socket.id)

    {:ok, socket}
  end

  @impl true
  def update(%{form: form} = assigns, socket) do
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
     |> assign(form: form)
     |> assign_new(:authorizing, fn -> false end)
     |> assign_new(:client, &build_client/0)
     |> assign_new(:authorize_url, fn %{client: client} ->
       OAuth2.Client.authorize_url!(client,
         state: build_state(socket.id, __MODULE__, assigns.id)
       )
     end)}
  end

  @impl true
  def update(%{code: code}, socket) do
    IO.inspect(code, label: "got a code")
    {:ok, socket |> assign(authorizing: false)}
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
    OAuth2.Client.new(
      strategy: OAuth2.Strategy.AuthCode,
      client_id: "client_id",
      client_secret: "abc123",
      site: "http://auth.example.com",
      redirect_uri: "http://localhost:4000/authenticate/callback"
    )
  end
end
