defmodule LightningWeb.Components.UserDeletionModal do
  @moduledoc false
  use LightningWeb, :component

  use Phoenix.LiveComponent

  alias Lightning.Accounts
  alias Lightning.Accounts.UserNotifier

  @impl true
  def update(%{user: user} = assigns, socket) do
    {:ok,
     socket
     |> assign(
       :scheduled_deletion_changeset,
       Accounts.change_scheduled_deletion(user)
     )
     |> assign(assigns)}
  end

  @impl true
  def handle_event(
        "validate_scheduled_deletion",
        %{"user" => user_params},
        socket
      ) do
    changeset =
      socket.assigns.user
      |> Accounts.change_scheduled_deletion(user_params)
      |> Map.put(:action, :validate_scheduled_deletion)

    {:noreply, assign(socket, :scheduled_deletion_changeset, changeset)}
  end

  @impl true
  def handle_event(
        "save_scheduled_deletion",
        %{
          "user" => %{
            "id" => _id,
            "scheduled_deletion_email" => email
          }
        } = _user_params,
        socket
      ) do
    case Accounts.schedule_user_deletion(socket.assigns.user, email) do
      {:ok, user} ->
        UserNotifier.send_deletion_notification_email(user)

        {:noreply,
         socket
         |> put_flash(:info, "User scheduled for deletion")
         |> logout_after_deletion()}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :scheduled_deletion_changeset, changeset)}
    end
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, push_redirect(socket, to: socket.assigns.return_to)}
  end

  defp logout_after_deletion(%{assigns: %{logout: true}} = socket),
    do: push_redirect(socket, to: Routes.user_session_path(socket, :delete))

  defp logout_after_deletion(%{assigns: %{logout: false}} = socket),
    do: push_redirect(socket, to: socket.assigns.return_to)

  @impl true
  def render(assigns) do
    ~H"""
    <div id={"user-#{@user.id}"}>
      <PetalComponents.Modal.modal
        max_width="sm"
        title="Delete user"
        close_modal_target={@myself}
      >
        <.form
          let={f}
          for={@scheduled_deletion_changeset}
          phx-change="validate_scheduled_deletion"
          phx-submit="save_scheduled_deletion"
          phx-target={@myself}
          id="scheduled_deletion_form"
        >
          <span>This user's account and credential data will be deleted</span>
          <div class="hidden sm:block" aria-hidden="true">
            <div class="py-2"></div>
          </div>
          <div class="grid grid-cols-12 gap-12">
            <div class="col-span-8">
              <%= label(f, :scheduled_deletion_email, "User email",
                class: "block text-sm font-medium text-secondary-700"
              ) %>
              <%= text_input(f, :scheduled_deletion_email,
                class: "block w-full rounded-md",
                phx_debounce: "blur"
              ) %>
              <%= error_tag(f, :scheduled_deletion_email,
                class:
                  "mt-1 focus:ring-primary-500 focus:border-primary-500 block w-full shadow-sm sm:text-sm border-secondary-300 rounded-md"
              ) %>
            </div>
          </div>

          <%= hidden_input(f, :id) %>

          <div class="hidden sm:block" aria-hidden="true">
            <div class="py-5"></div>
          </div>
          <div class="flex justify-end">
            <PetalComponents.Button.button
              label="Cancel"
              phx-click={PetalComponents.Modal.hide_modal(@myself)}
            />

            <%= submit("Delete account",
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
