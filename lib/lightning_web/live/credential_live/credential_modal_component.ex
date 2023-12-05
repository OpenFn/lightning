defmodule LightningWeb.CredentialLive.CredentialModalComponent do
  @moduledoc false
  alias Lightning.Credentials
  use LightningWeb, :live_component

  alias Phoenix.LiveView.JS
  alias Lightning.Credentials.Credential

  @impl true
  def update(assigns, socket) do
    {:ok, apply_action(socket, assigns.action, assigns)}
  end

  defp apply_action(socket, :new, assigns) do
    socket
    |> assign(assigns)
    |> assign(is_form_valid: false)
    |> assign(action: :new)
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div class="text-xs">
      <.modal
        id={@id}
        phx-fragment-match={show_modal(@id)}
        phx-hook="FragmentMatch"
        width="min-w-1/3 max-w-full"
      >
        <:title>
          <div class="flex justify-between">
            <span class="font-bold">
              Add a credential
            </span>
            <button
              phx-click="close_modal"
              phx-target={@myself}
              type="button"
              class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
              aria-label={gettext("close")}
            >
              <span class="sr-only">Close</span>
              <Heroicons.x_mark solid class="h-5 w-5 stroke-current" />
            </button>
          </div>
        </:title>
        <.live_component
          module={LightningWeb.CredentialLive.FormComponent}
          id={:new}
          action={:new}
          type={@selected_credential_type}
          credential={@credential}
          projects={[]}
          project={@project}
          on_save={nil}
          show_project_credentials={false}
        />
        <.modal_footer class="mt-6 mx-6">
          <div class="sm:flex sm:flex-row-reverse">
            <button
              type="submit"
              disabled={!@selected_credential_type}
              phx-click="credential_type_selected"
              phx-target={@myself}
              class="inline-flex w-full justify-center rounded-md disabled:bg-primary-300 bg-primary-600 px-3 py-2 text-sm font-semibold text-white shadow-sm hover:bg-primary-500 sm:ml-3 sm:w-auto"
            >
              Configure credential
            </button>
            <button
              type="button"
              phx-click={JS.navigate(@return_to)}
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
