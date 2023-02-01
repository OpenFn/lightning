defmodule LightningWeb.CredentialLive.GoogleSheetsLive do
  use LightningWeb, :live_component

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
    <div class="">
      <.google_signin authorize_url={@authorize_url} socket={@socket} />
    </div>
    """
  end

  def google_signin(assigns) do
    ~H"""
    <fieldset>
      <legend class="contents text-base font-medium text-gray-900">
        Details
      </legend>
      <p class="text-sm text-gray-500">
        Configuration for this credential.
      </p>

      <.link href={@authorize_url} target="_blank" class="google-authorize group">
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
    </fieldset>
    """
  end

  @impl true
  def mount(socket) do
    {:ok, socket}
  end

  @impl true
  def update(assigns, socket) do
    IO.inspect(assigns)

    {:ok,
     socket
     |> assign_new(:client, &build_client/0)
     |> assign_new(:authorize_url, fn %{client: client} ->
       OAuth2.Client.authorize_url!(client)
     end)}
  end

  defp build_client() do
    OAuth2.Client.new(
      strategy: OAuth2.Strategy.AuthCode,
      client_id: "client_id",
      client_secret: "abc123",
      site: "https://auth.example.com",
      redirect_uri: "https://example.com/auth/callback"
    )
  end
end
