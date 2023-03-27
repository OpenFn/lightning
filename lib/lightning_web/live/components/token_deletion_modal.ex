defmodule LightningWeb.Components.TokenDeletionModal do
  @moduledoc false
  use LightningWeb, :component

  use Phoenix.LiveComponent

  alias Lightning.Accounts

  @impl true
  def update(%{id: id} = assigns, socket) do
    {:ok,
     socket
     |> assign(
       :delete_token_changeset,
       Accounts.get_token!(id)
     )
     |> assign(:new_token, nil)
     |> assign(assigns)}
  end

  @impl true
  def handle_event("delete_token", %{"id" => id}, socket) do
    token = Accounts.get_token!(id)

    Accounts.delete_token(token)
    |> case do
      :ok ->
        {:noreply,
         socket
         |> assign(
           :tokens,
           Accounts.list_api_tokens(socket.assigns.current_user)
         )
         |> assign(:new_token, nil)
         |> put_flash(:info, "Token deleted successfully")}
    end
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, push_redirect(socket, to: socket.assigns.return_to)}
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"token-#{@id}"}>
      <PetalComponents.Modal.modal
        max_width="sm"
        title="Delete API Access Token"
        close_modal_target={@myself}
      >
        <.form
          :let={f}
          for={@delete_token_changeset}
          as={:token}
          phx-submit="delete_token"
          phx-target={@myself}
          id="token_deletion_form"
        >
          <span>
            Any applications or scripts using this token will no longer be able to access the API. You cannot undo this action. Are you sure you want to delete this token?
          </span>

          <%= hidden_input(f, :id) %>

          <div class="hidden sm:block" aria-hidden="true">
            <div class="py-5"></div>
          </div>
          <div class="flex justify-end">
            <PetalComponents.Button.button
              label="Cancel"
              phx-click={PetalComponents.Modal.hide_modal(@myself)}
            />

            <%= submit("Delete token",
              phx_disable_with: "Deleting...",
              class:
                "inline-flex justify-center mx-2 py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-danger-500 hover:bg-danger-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-danger-500"
            ) %>
          </div>
        </.form>
      </PetalComponents.Modal.modal>
    </div>
    """
  end
end
