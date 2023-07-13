defmodule LightningWeb.ProfileLive.MfaComponent do
  @moduledoc """
  Component to enable MFA on a User's account
  """
  use LightningWeb, :live_component

  alias Lightning.Accounts

  @impl true
  def update(%{user: user} = assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(
       show: user.mfa_enabled,
       current_totp: Accounts.get_user_totp(user),
       editing_totp: nil,
       totp_changeset: nil,
       qrcode_uri: nil
     )}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="bg-white shadow-sm ring-1 ring-gray-900/5 sm:rounded-xl md:col-span-2 mb-4">
      <div class="px-4 py-6 sm:p-8">
        <div class="flex items-center justify-between mb-5">
          <span class="flex flex-grow flex-col">
            <span
              class="text-xl font-medium leading-6 text-gray-900"
              id={"#{@id}-label"}
            >
              Enable multi-factor authentication
            </span>
            <span class="text-sm text-gray-500" id={"#{@id}-description"}>
              This adds an additional layer of security to your account by requiring more than just a password to sign in.
            </span>
          </span>
          <button
            type="button"
            class={"#{if @show, do: "bg-indigo-600", else: "bg-gray-200"} relative inline-flex h-6 w-11 flex-shrink-0 cursor-pointer rounded-full border-2 border-transparent transition-colors duration-200 ease-in-out focus:outline-none focus:ring-2 focus:ring-indigo-600 focus:ring-offset-2"}
            role="switch"
            phx-click={if @show, do: "hide-mfa-options", else: "show-mfa-options"}
            phx-target={@myself}
            aria-checked={@show}
            aria-labelledby={"#{@id}-label"}
            aria-describedby={"#{@id}-description"}
          >
            <span
              aria-hidden="true"
              class={"#{if @show, do: "translate-x-5", else: "translate-x-0"} pointer-events-none inline-block h-5 w-5 transform rounded-full bg-white shadow ring-0 transition duration-200 ease-in-out"}
            >
            </span>
          </button>
        </div>
        <div :if={@editing_totp} class="">
          <div>
            <h3 class="text-base font-semibold leading-6 text-gray-900">
              Authenticator app
            </h3>
            <p class="mt-2 max-w-4xl text-sm text-gray-500">
              Authenticator apps and browser extensions like 1Password, Authy etc. generate one-time passwords
              that are used as a second factor to verify your identity when prompted during sign-in.
            </p>
          </div>
          <div>
            <h3 class="text-base font-semibold leading-6 text-gray-900">
              Scan the QR code
            </h3>
            <p class="mt-2 max-w-4xl text-sm text-gray-500">
              Use an authenticator app or browser extension to scan.
            </p>
            <div>
              <%= generate_qrcode(@qrcode_uri) %>
            </div>
            <p class="mt-2 max-w-4xl text-sm text-gray-500">
              Unable to scan? You can use the secret key below to manually configure your authenticator app.
              <br />
              <code><%= Base.encode32(@editing_totp.secret, padding: false) %></code>
            </p>
          </div>
        </div>
      </div>
    </div>
    """
  end

  @impl true
  def handle_event("show-mfa-options", _params, %{assigns: assigns} = socket) do
    app = "OpenFn"
    secret = NimbleTOTP.secret()

    qrcode_uri =
      NimbleTOTP.otpauth_uri("#{app}:#{assigns.user.email}", secret, issuer: app)

    editing_totp =
      assigns.current_totp ||
        %Accounts.UserTOTP{user_id: assigns.user.id, secret: secret}

    totp_changeset = Accounts.UserTOTP.changeset(editing_totp, %{})

    {:noreply,
     assign(socket,
       show: true,
       editing_totp: editing_totp,
       totp_changeset: totp_changeset,
       qrcode_uri: qrcode_uri
     )}
  end

  def handle_event("hide-mfa-options", _params, socket) do
    {:noreply, socket}
  end

  defp generate_qrcode(uri) do
    uri
    |> EQRCode.encode()
    |> EQRCode.svg(width: 264)
    |> raw()
  end
end
