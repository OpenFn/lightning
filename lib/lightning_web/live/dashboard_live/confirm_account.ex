defmodule LightningWeb.AccountConfirmationModal do
  use LightningWeb, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="text-xs">
      <.modal show={true} id={@id} width="xl:min-w-1/3 min-w-1/2 w-1/2">
        <:title>
          <div class="flex justify-between">
            <span class="font-bold">Confirm your account</span>
          </div>
        </:title>
        <div class="container mx-auto px-6 space-y-6 bg-white text-base text-gray-600">
        For security purposes, we have blocked access to your accounts, projects and workflows until you confirm your account. Please click resend confirmation email to receive instructions on how to confirm your OpenFn account or update your email address if you have not received a confirmation email.
      </div>

        <.modal_footer class="mt-6 mx-6">
            <div class="sm:flex sm:flex-row-reverse">
              <button
                type="submit"
                phx-target={@myself}
                class="inline-flex w-full justify-center rounded-md disabled:bg-primary-300 bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 sm:ml-3 sm:w-auto"
              >
              Resend confirmation email              </button>
              <button
                id="cancel-project-creation"
                type="button"
                phx-click="close_modal"
                phx-target={@myself}
                class="mt-3 inline-flex w-full justify-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:mt-0 sm:w-auto"
              >
              Update email address
              </button>
            </div>
          </.modal_footer>
      </.modal>
    </div>
    """
  end
end
