defmodule LightningWeb.AccountConfirmationModal do
  use LightningWeb, :live_component

  @impl true
  def update(%{email_sent: email_sent}, socket) do
    {:ok, assign(socket, :email_sent, email_sent)}
  end

  def update(assigns, socket) do
    {:ok, socket |> assign(assigns) |> assign(:email_sent, false)}
  end

  @impl true
  def handle_event("resend-confirmation-email", _, socket) do
    Lightning.Accounts.deliver_user_confirmation_instructions(
      socket.assigns.current_user
    )

    send_update_after(
      self(),
      __MODULE__,
      [id: socket.assigns.id, email_sent: false],
      5000
    )

    {:noreply, assign(socket, :email_sent, true)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="text-xs">
      <.modal
        show={true}
        close_on_keydown={false}
        close_on_click_away={false}
        id={@id}
        width="xl:min-w-1/3 min-w-1/2 w-1/2"
      >
        <:title>
          <div class="flex justify-between">
            <span class="font-bold">Confirm your account</span>
          </div>
        </:title>
        <div class="container mx-auto px-6 space-y-6 bg-white text-base text-gray-600">
          For security purposes, we have blocked access to your accounts, projects and workflows until you confirm your account. Please click resend confirmation email to receive instructions on how to confirm your OpenFn account or update your email address if you have not received a confirmation email.
        </div>

        <.modal_footer class="mt-6 mx-6 flex items-center justify-between">
          <!-- Confirmation alert or spacer -->
          <div class="flex-grow">
            <div :if={@email_sent} class="flex items-center">
              <div class="flex-shrink-0">
                <.icon name="hero-check-circle-solid" class="h-5 w-5 text-green-400" />
              </div>
              <div class="ml-2">
                <p class="text-sm font-medium text-green-800">
                  Confirmation email sent successfully
                </p>
              </div>
            </div>
          </div>
          <!-- Buttons on the right -->
          <div class="flex-none">
            <button
              id="update-email-address-button"
              type="button"
              phx-target={@myself}
              class="inline-flex justify-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:w-auto"
            >
              Update email address
            </button>
            <button
              id="resend-confirmation-email-button"
              type="button"
              phx-click="resend-confirmation-email"
              phx-target={@myself}
              class="ml-3 inline-flex justify-center rounded-md disabled:bg-primary-300 bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 sm:w-auto"
            >
              Resend confirmation email
            </button>
          </div>
        </.modal_footer>
      </.modal>
    </div>
    """
  end
end
