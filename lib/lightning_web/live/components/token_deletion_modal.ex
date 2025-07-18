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
      <.modal id={"delete-token-modal-#{@id}"} width="max-w-md" show={true}>
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
        <.modal_footer>
          <.button
            id={"delete-token-#{@id}_confirm_button"}
            type="button"
            phx-target={@myself}
            phx-click="delete_token"
            phx-value-id={@id}
            theme="danger"
            phx-disable-with="Deleting..."
          >
            Yes
          </.button>
          <.button
            type="button"
            phx-click="close_modal"
            phx-target={@myself}
            theme="secondary"
          >
            Cancel
          </.button>
        </.modal_footer>
      </.modal>
    </div>
    """
  end
end
