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
    Lightning.Accounts.remind_account_confirmation(socket.assigns.current_user)

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
        <div class="container mx-auto px-6 space-y-6 text-base text-gray-600">
          <div>
            This account has been blocked pending email confirmation. Please
            check your email for a confirmation link, request that a new link be
            sent, or update your email address to keep using OpenFn.
          </div>
          <Common.alert :if={@email_sent} type="info">
            <:message>
              A new link has been sent. Please check your email.
            </:message>
          </Common.alert>
        </div>
        <.modal_footer class="mt-6 mx-6">
          <div class="sm:flex sm:flex-row-reverse">
            <button
              id="resend-confirmation-email-button"
              type="button"
              phx-click="resend-confirmation-email"
              phx-target={@myself}
              disabled={@email_sent}
              class="ml-3 inline-flex justify-center rounded-md disabled:bg-primary-300 bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 sm:w-auto"
            >
              Resend confirmation email
            </button>
            <.link
              href={~p"/profile"}
              class="inline-flex justify-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:w-auto"
            >
              Update email address
            </.link>
          </div>
        </.modal_footer>
      </.modal>
    </div>
    """
  end
end
