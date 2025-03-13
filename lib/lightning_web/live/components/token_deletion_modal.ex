defmodule LightningWeb.Components.TokenDeletionModal do
  @moduledoc false
  use LightningWeb, :component
  use Phoenix.LiveComponent
  alias Lightning.Accounts

  @impl true
  def update(%{id: id} = assigns, socket) do
    {:ok, socket |> assign(id: id, return_to: assigns.return_to)}
  end

  @impl true
  def handle_event("delete_token", %{"id" => id}, socket) do
    token = Accounts.get_token!(id)

    Accounts.delete_token(token)
    |> case do
      {:ok, _} ->
        {:noreply,
         socket
         |> put_flash(:info, "Token deleted successfully")
         |> push_navigate(to: socket.assigns.return_to)}

      {:error, _changeset} ->
        {:noreply, socket |> put_flash(:error, "Something went wrong.")}
    end
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, push_navigate(socket, to: socket.assigns.return_to)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <.modal id={"delete-token-#{@id}"} width="max-w-md" show={true}>
        <:title>
          <div class="flex justify-between">
            <span class="font-bold">
              Delete API Access Token
            </span>

            <button
              phx-click="close_modal"
              phx-target={@myself}
              type="button"
              class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
              aria-label={gettext("close")}
            >
              <span class="sr-only">Close</span>
              <.icon name="hero-x-mark" class="h-5 w-5 stroke-current" />
            </button>
          </div>
        </:title>
        <div class="">
          <p class="text-sm text-gray-500">
            Any applications or scripts using this token will no longer be able to access the API.
            You cannot undo this action. <br />
            Are you sure you want to delete this token?
          </p>
        </div>
        <div class="flex-grow bg-gray-100 h-0.5 my-[16px]"></div>
        <div class="flex flex-row-reverse gap-4">
          <.button
            id={"delete-token-#{@id}_confirm_button"}
            type="button"
            phx-target={@myself}
            phx-click="delete_token"
            phx-value-id={@id}
            color_class="bg-red-600 hover:bg-red-700 text-white"
            phx-disable-with="Deleting..."
          >
            Yes
          </.button>
          <button
            type="button"
            phx-click="close_modal"
            phx-target={@myself}
            class="inline-flex items-center rounded-md bg-white px-3.5 py-2.5 text-sm font-semibold text-gray-900 shadow-xs ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
          >
            Cancel
          </button>
        </div>
      </.modal>
    </div>
    """
  end
end
