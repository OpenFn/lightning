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
        <div class="relative">
          <div class="absolute inset-0 flex items-center" aria-hidden="true">
            <div class="w-full border-t border-gray-300"></div>
          </div>
        </div>

        <div :if={@current_totp && is_nil(@editing_totp)} class="">
          <div class="py-5 text-sm">
            You've configured an authentication app to get two-factor authentication codes.
            <a
              href="#"
              phx-click="show-mfa-options"
              phx-target={@myself}
              class="font-medium text-blue-600 dark:text-blue-500 hover:underline"
            >
              Setup another device instead
            </a>
          </div>
        </div>

        <div :if={@editing_totp} class="py-5">
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
              Unable to scan? You can use
              <a
                href="#"
                class="font-medium text-blue-600 dark:text-blue-500 hover:underline"
                phx-click={show_modal("mfa-secret-modal")}
              >
                this secret key
              </a>
              to manually configure your authenticator app.
            </p>
            <.form
              :let={f}
              for={@totp_changeset}
              phx-submit="save_totp"
              phx-target={@myself}
              class="mt-2"
            >
              <div class="grid max-w-2xl grid-cols-1 gap-x-6 gap-y-8 sm:grid-cols-6">
                <div class="sm:col-span-4">
                  <%= label(f, :code, "Verify the code from the app",
                    class: "block font-medium text-secondary-700"
                  ) %>
                  <%= text_input(f, :code,
                    class: "block rounded-md",
                    autocomplete: "off",
                    placeholder: "XXXXXX"
                  ) %>
                  <%= error_tag(f, :code,
                    class:
                      "mt-1 focus:ring-primary-500 focus:border-primary-500 block w-full shadow-sm sm:text-sm border-secondary-300 rounded-md"
                  ) %>
                </div>

                <div class="col-span-6">
                  <span>
                    <.link
                      phx-click="hide-mfa-options"
                      phx-target={@myself}
                      class="inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-secondary-700 hover:bg-secondary-800 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-secondary-500"
                    >
                      Cancel
                    </.link>
                  </span>
                  <span>
                    <%= submit("Save",
                      phx_disable_with: "Saving...",
                      class:
                        "inline-flex justify-center py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-primary-600 hover:bg-primary-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-primary-500"
                    ) %>
                  </span>
                </div>
              </div>
            </.form>
          </div>
          <div
            id="mfa-secret-modal"
            class="relative z-10 hidden"
            aria-labelledby="mfa-secret-modal-title"
            role="dialog"
            aria-modal="true"
            phx-remove={hide_modal("mfa-secret-modal")}
          >
            <div
              id="mfa-secret-modal-bg"
              class="fixed inset-0 bg-gray-500 bg-opacity-75 transition-opacity"
            >
            </div>

            <div class="fixed inset-0 z-10 overflow-y-auto">
              <div class="flex min-h-full items-end justify-center p-4 text-center sm:items-center sm:p-0">
                <.focus_wrap
                  id="mfa-secret-modal-container"
                  phx-window-keydown={hide_modal("mfa-secret-modal")}
                  phx-key="escape"
                  phx-click-away={hide_modal("mfa-secret-modal")}
                  class="relative transform overflow-hidden rounded-lg bg-white px-4 pb-4 pt-5 text-left shadow-xl transition-all sm:my-8 sm:w-full sm:max-w-lg sm:p-6"
                >
                  <div class="absolute right-0 top-0 hidden pr-4 pt-4 sm:block">
                    <button
                      type="button"
                      phx-click={hide_modal("mfa-secret-modal")}
                      class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none focus:ring-2 focus:ring-indigo-500 focus:ring-offset-2"
                    >
                      <span class="sr-only">Close</span>
                      <svg
                        class="h-6 w-6"
                        fill="none"
                        viewBox="0 0 24 24"
                        stroke-width="1.5"
                        stroke="currentColor"
                        aria-hidden="true"
                      >
                        <path
                          stroke-linecap="round"
                          stroke-linejoin="round"
                          d="M6 18L18 6M6 6l12 12"
                        />
                      </svg>
                    </button>
                  </div>
                  <div class="sm:flex sm:items-start">
                    <div
                      class="mt-3 text-center sm:ml-4 sm:mt-0 sm:text-left"
                      id="mfa-secret-modal-content"
                    >
                      <h3
                        class="text-base font-semibold leading-6 text-gray-900"
                        id="mfa-secret-modal-title"
                      >
                        Your two-factor secret
                      </h3>
                      <div class="mt-2">
                        <p class="text-sm text-gray-500">
                          <code>
                            <%= Base.encode32(@editing_totp.secret, padding: false) %>
                          </code>
                        </p>
                      </div>
                    </div>
                  </div>
                </.focus_wrap>
              </div>
            </div>
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
      assigns.current_totp || %Accounts.UserTOTP{user_id: assigns.user.id}

    editing_totp = %{editing_totp | secret: secret}

    totp_changeset = Accounts.UserTOTP.changeset(editing_totp, %{})

    {:noreply,
     assign(socket,
       show: true,
       editing_totp: editing_totp,
       totp_changeset: totp_changeset,
       qrcode_uri: qrcode_uri
     )}
  end

  def handle_event("hide-mfa-options", _params, %{assigns: assigns} = socket) do
    {:noreply, assign(socket, editing_totp: nil, show: assigns.user.mfa_enabled)}
  end

  def handle_event("save_totp", %{"user_totp" => params}, socket) do
    editing_totp = socket.assigns.editing_totp

    case Accounts.upsert_user_totp(editing_totp, params) do
      {:ok, _totp} ->
        {:noreply,
         socket
         |> put_flash(:info, "2FA Enabled successfully!")
         |> push_patch(to: ~p"/profile", replace: true)}

      {:error, changeset} ->
        {:noreply, assign(socket, totp_changeset: changeset)}
    end
  end

  defp generate_qrcode(uri) do
    uri
    |> EQRCode.encode()
    |> EQRCode.svg(width: 264)
    |> raw()
  end
end
