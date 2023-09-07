defmodule LightningWeb.Components.CredentialDeletionModal do
  @moduledoc false
  alias Lightning.Credentials
  use LightningWeb, :component

  use Phoenix.LiveComponent

  alias Lightning.Accounts
  alias Lightning.Accounts.User

  @impl true
  def update(%{credential: credential} = assigns, socket) do
    {:ok,
     socket
     |> assign(
       delete_now?: !is_nil(credential.scheduled_deletion),
       has_activity_in_projects?:
         Credentials.has_activity_in_projects?(credential)
     )
     |> assign(assigns)}
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    credential = Credentials.get_credential!(id)

    can_delete_credential =
      Lightning.Policies.Users
      |> Lightning.Policies.Permissions.can?(
        :delete_credential,
        socket.assigns.current_user,
        credential
      )

    has_activity_in_projects = Credentials.has_activity_in_projects?(credential)

    cond do
      not can_delete_credential ->
        {:noreply,
         put_flash(socket, :error, "You can't perform this action")
         |> push_patch(to: ~p"/credentials")}

      has_activity_in_projects ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Cannot delete a credential that has activities in projects"
         )}

      true ->
        Credentials.delete_credential(credential)
        |> case do
          {:ok, _} ->
            {:noreply,
             socket
             |> put_flash(:info, "Credential deleted successfully")
             |> push_patch(to: ~p"/credentials")}

          {:error, _changeset} ->
            {:noreply, socket |> put_flash(:error, "Can't delete credential")}
        end
    end
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, push_redirect(socket, to: ~p"/credentials")}
  end

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
          This credential can't be deleted for now. It is involved in projects that has ongoing activities.
        </p>
        <div class="flex justify-end">
          <PetalComponents.Button.button
            label="Ok, understood"
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
