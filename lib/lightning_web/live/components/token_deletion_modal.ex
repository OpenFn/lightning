# defmodule LightningWeb.Components.TokenDeletionModal do
#   @moduledoc false
#   use LightningWeb, :component

#   use Phoenix.LiveComponent

#   alias Lightning.Accounts

#   @impl true
#   def update(%{user: user} = assigns, socket) do
#     {:ok,
#      socket
#      |> assign(
#        :scheduled_deletion_changeset,
#        Accounts.change_scheduled_deletion(user)
#      )
#      |> assign(assigns)}
#   end

#   @impl true
#   def handle_event("delete_token", %{"id" => id}, socket) do
#     token = Accounts.get_token!(id).token

#     Accounts.delete_api_token(token)
#     |> case do
#       :ok ->
#         {:noreply,
#          socket
#          |> assign(
#            :tokens,
#            get_tokens(socket.assigns.current_user)
#          )
#          |> assign(:new_token, nil)
#          |> put_flash(:info, "Token deleted successfully")}
#     end
#   end

#   @impl true
#   def handle_event("close_modal", _, socket) do
#     {:noreply, push_redirect(socket, to: socket.assigns.return_to)}
#   end

#   @impl true
#   def render(assigns) do
#     ~H"""
#     <div id={"user-#{@user.id}"}>
#       <PetalComponents.Modal.modal
#         max_width="sm"
#         title="Delete user"
#         close_modal_target={@myself}
#       >
#         <.form
#           :let={f}
#           for={@scheduled_deletion_changeset}
#           phx-submit="delete_token"
#           phx-target={@myself}
#           id="token_deletion_form"
#           User
#         >
#           <span>This user's account and credential data will be deleted</span>

#           <%= hidden_input(f, :id) %>

#           <div class="hidden sm:block" aria-hidden="true">
#             <div class="py-5"></div>
#           </div>
#           <div class="flex justify-end">
#             <PetalComponents.Button.button
#               label="Cancel"
#               phx-click={PetalComponents.Modal.hide_modal(@myself)}
#             />

#             <%= submit("Delete account",
#               phx_disable_with: "Deleting...",
#               class:
#                 "inline-flex justify-center mx-2 py-2 px-4 border border-transparent shadow-sm text-sm font-medium rounded-md text-white bg-danger-500 hover:bg-danger-700 focus:outline-none focus:ring-2 focus:ring-offset-2 focus:ring-danger-500"
#             ) %>
#           </div>
#         </.form>
#       </PetalComponents.Modal.modal>
#     </div>
#     """
#   end
# end
