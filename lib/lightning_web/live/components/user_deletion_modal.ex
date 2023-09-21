defmodule LightningWeb.Components.UserDeletionModal do
  @moduledoc false
  use LightningWeb, :component

  use Phoenix.LiveComponent

  alias Lightning.Accounts
  alias Lightning.Accounts.User

  @impl true
  def update(%{user: user} = assigns, socket) do
    {:ok,
     socket
     |> assign(
       delete_now?: !is_nil(user.scheduled_deletion),
       has_activity_in_projects?: Accounts.has_activity_in_projects?(user),
       scheduled_deletion_changeset: Accounts.change_scheduled_deletion(user)
     )
     |> assign(assigns)}
  end

  @impl true
  def handle_event(
        "validate",
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
  def handle_event("delete", %{"user" => user_params}, socket) do
    cond do
      not socket.assigns.delete_now? ->
        case Accounts.schedule_user_deletion(
               socket.assigns.user,
               user_params["scheduled_deletion_email"]
             ) do
          {:ok, %User{}} ->
            {:noreply,
             socket
             |> put_flash(:info, "User scheduled for deletion")
             |> logout_after_deletion()}

          {:error, %Ecto.Changeset{} = changeset} ->
            {:noreply, assign(socket, :scheduled_deletion_changeset, changeset)}
        end

      socket.assigns.has_activity_in_projects? ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Cannot delete user that has activities in other projects"
         )
         |> push_navigate(to: ~p"/settings/users")}

      true ->
        Accounts.purge_user(socket.assigns.user.id)

        {:noreply,
         socket
         |> put_flash(:info, "User deleted")
         |> push_navigate(to: ~p"/settings/users")}
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
  def render(%{delete_now?: true, has_activity_in_projects?: true} = assigns) do
    ~H"""
    <div id={"user-#{@id}"}>
      <PetalComponents.Modal.modal
        max_width="sm"
        title="Delete user"
        close_modal_target={@myself}
      >
        <p>
          This user cannot be deleted until their auditable activities have also been purged.
        </p>
        <div class="hidden sm:block" aria-hidden="true">
          <div class="py-2"></div>
        </div>
        <p>
          Audit trails are removed on a project-basis and may be controlled by the project owner or a superuser.
        </p>
        <div class="flex justify-end">
          <PetalComponents.Button.button
            label="Cancel"
            phx-click={PetalComponents.Modal.hide_modal(@myself)}
          />
        </div>
      </PetalComponents.Modal.modal>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div id={"user-#{@id}"}>
      <PetalComponents.Modal.modal
        max_width="sm"
        title="Delete user"
        close_modal_target={@myself}
      >
        <.form
          :let={f}
          for={@scheduled_deletion_changeset}
          phx-change="validate"
          phx-submit="delete"
          phx-target={@myself}
          id="scheduled_deletion_form"
        >
          <span>
            This user's account and credential data will be deleted. Please make sure none of these credentials are used in production workflows.
          </span>

          <%= if @has_activity_in_projects? do %>
            <div class="hidden sm:block" aria-hidden="true">
              <div class="py-2"></div>
            </div>
            <p>
              *Note that this user still has activity related to active projects. We may not be able to delete them entirely from the app until those projects are deleted.
            </p>
          <% end %>
          <div class="hidden sm:block" aria-hidden="true">
            <div class="py-2"></div>
          </div>
          <div class="grid grid-cols-12 gap-12">
            <div class="col-span-8">
              <%= Phoenix.HTML.Form.label(f, :scheduled_deletion_email, "User email",
                class: "block text-sm font-medium text-secondary-700"
              ) %>
              <%= Phoenix.HTML.Form.text_input(f, :scheduled_deletion_email,
                class: "block w-full rounded-md",
                phx_debounce: "blur"
              ) %>
              <.old_error field={f[:scheduled_deletion_email]} />
            </div>
          </div>

          <%= Phoenix.HTML.Form.hidden_input(f, :id) %>

          <div class="hidden sm:block" aria-hidden="true">
            <div class="py-5"></div>
          </div>
          <div class="flex justify-end">
            <PetalComponents.Button.button
              label="Cancel"
              phx-click={PetalComponents.Modal.hide_modal(@myself)}
            /> &nbsp;
            <LightningWeb.Components.Common.button
              type="submit"
              color="red"
              phx-disable-with="Deleting..."
              disabled={!@scheduled_deletion_changeset.valid?}
            >
              Delete account
            </LightningWeb.Components.Common.button>
          </div>
        </.form>
      </PetalComponents.Modal.modal>
    </div>
    """
  end
end
