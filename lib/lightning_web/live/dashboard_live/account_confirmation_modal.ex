defmodule LightningWeb.AccountConfirmationModal do
  @moduledoc """
  A LiveView component for displaying an account confirmation modal.

  This component is responsible for informing users that access to their
  accounts, projects, and workflows is restricted until they confirm
  their account. It provides functionality to resend the confirmation
  email and allows users to update their email address if needed.

  ## Features

  - Displays a modal with instructions for account confirmation.
  - Allows users to resend the confirmation email.
  - Provides feedback when the confirmation email is successfully sent.
  - Allows users to navigate to the profile page to update their email address.

  ## Usage

  Include this component in your LiveView template where you need to prompt
  users to confirm their account. The component determines whether the modal
  should be shown based on the current view context.

  ## Examples

      <.live_component
        module={LightningWeb.AccountConfirmationModal}
        id="account-confirmation-modal"
        current_user={@current_user}
      />

  The component uses assigns to manage its state, including:

  - `:show_modal` - Determines if the modal should be visible.
  - `:email_sent` - Indicates if the confirmation email was successfully sent.
  """
  use LightningWeb, :live_component

  @impl true
  def update(%{email_sent: email_sent}, socket) do
    {:ok, assign(socket, :email_sent, email_sent)}
  end

  def update(assigns, socket) do
    show_modal =
      case socket.view do
        LightningWeb.ProfileLive.Edit -> false
        _ -> true
      end

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:show_modal, show_modal)
     |> assign(:email_sent, false)}
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
        id={@id}
        show={@show_modal}
        close_on_keydown={false}
        close_on_click_away={false}
        width="xl:min-w-1/3 min-w-1/2 w-1/3"
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
          <div class="flex-none">
            <.link
              href={~p"/profile"}
              class="inline-flex justify-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:w-auto"
            >
              Update email address
            </.link>
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
