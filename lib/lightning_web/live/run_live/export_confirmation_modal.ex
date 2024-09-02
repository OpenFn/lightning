defmodule LightningWeb.RunLive.ExportConfirmationModal do
  use LightningWeb, :live_component

  @impl true
  def update(assigns, socket) do
    {:ok, socket |> assign(assigns)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="text-xs">
      <.modal id={@id} show={true} width="w-1/3">
        <:title>
          <div class="flex justify-between">
            <span class="font-bold">Confirm history export</span>
            <button
              id="close-export-modal"
              phx-click="close-export-modal"
              type="button"
              class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
              aria-label={gettext("close")}
            >
              <span class="sr-only">Close</span>
              <Heroicons.x_mark solid class="h-5 w-5 stroke-current" />
            </button>
          </div>
        </:title>
        <div class="container mx-auto px-6 space-y-6 bg-white text-sm text-slate-900">
          Exporting history will download all <%= @count_work_orders %> work orders and associated runs, steps, and I/O data clips that match your query.<br />
          The export will happen in the background and you'll receive an email when it is complete.
        </div>
        <.modal_footer class="mt-6 mx-6">
          <div class="sm:flex sm:flex-row-reverse">
            <button
              id="confirm-export"
              type="button"
              phx-click="confirm-export"
              class="inline-flex w-full justify-center rounded-md disabled:bg-primary-300 bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 sm:ml-3 sm:w-auto"
            >
              Export history
            </button>
            <button
              id="cancel-export"
              type="button"
              phx-click="close-export-modal"
              class="mt-3 inline-flex w-full justify-center rounded-md bg-white px-3 py-2 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50 sm:mt-0 sm:w-auto"
            >
              Cancel
            </button>
          </div>
        </.modal_footer>
      </.modal>
    </div>
    """
  end
end
