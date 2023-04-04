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
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, _changeset} ->
        {:noreply, socket |> put_flash(:error, "Something went wrong.")}
    end
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, push_redirect(socket, to: socket.assigns.return_to)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div>
      <PetalComponents.Modal.modal
        max_width="sm"
        title="Delete API Access Token"
        close_modal_target={@myself}
      >
        <span>
          Any applications or scripts using this token will no longer be able to access the API. You cannot undo this action. Are you sure you want to delete this token?
        </span>

        <div class="hidden sm:block" aria-hidden="true">
          <div class="py-5"></div>
        </div>
        <div class="flex justify-end">
          <PetalComponents.Button.button
            label="Cancel"
            phx-click={PetalComponents.Modal.hide_modal(@myself)}
          />

          <PetalComponents.Button.button
            label="Yes"
            color="danger"
            phx-target={@myself}
            phx-click="delete_token"
            phx-value-id={@id}
            class="mx-2"
          />
        </div>
      </PetalComponents.Modal.modal>
    </div>
    """
  end
end
