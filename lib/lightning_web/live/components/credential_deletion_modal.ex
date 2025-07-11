defmodule LightningWeb.Components.CredentialDeletionModal do
  @moduledoc false

  use LightningWeb, :component
  use Phoenix.LiveComponent

  alias Lightning.Credentials
  alias Lightning.Credentials.Credential

  @impl true
  def update(
        %{credential: credential, return_to: _} = assigns,
        socket
      ) do
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

    cond do
      not socket.assigns.delete_now? ->
        case Credentials.schedule_credential_deletion(credential) do
          {:ok, %Credential{}} ->
            {:noreply,
             socket
             |> put_flash(:info, "Credential scheduled for deletion")
             |> push_navigate(to: socket.assigns.return_to)}

          {:error, %Ecto.Changeset{} = _changeset} ->
            {:noreply, socket}
        end

      socket.assigns.has_activity_in_projects? ->
        {:noreply,
         socket
         |> put_flash(
           :error,
           "Cannot delete a credential that has activities in projects"
         )
         |> push_patch(to: socket.assigns.return_to)}

      true ->
        Credentials.delete_credential(credential)

        {:noreply,
         socket
         |> put_flash(:info, "Credential deleted successfully")
         |> push_navigate(to: socket.assigns.return_to)}
    end
  end

  @impl true
  def render(%{delete_now?: true, has_activity_in_projects?: true} = assigns) do
    ~H"""
    <div>
      <LightningWeb.Components.Credentials.credential_modal id={"credential-#{@id}"}>
        <:title>
          Credential marked for deletion
        </:title>
        <div class="text-sm text-gray-500">
          <p>
            This credential has been used in workflow runs that
            are still monitored in at least one project's audit trail. The
            credential will be made unavailable for future use immediately and
            after a cooling-off period all secrets will be permanently scrubbed,
            but the record itself will not be removed until related workflow
            runs have been purged.
          </p>
          <p class="py-2">
            Contact your instance administrator for more details.
          </p>
        </div>
        <.modal_footer>
          <LightningWeb.Components.Credentials.credential_modal_cancel_button modal_id={"credential-#{@id}"}>
            Ok, understood
          </LightningWeb.Components.Credentials.credential_modal_cancel_button>
        </.modal_footer>
      </LightningWeb.Components.Credentials.credential_modal>
    </div>
    """
  end

  def render(assigns) do
    ~H"""
    <div>
      <LightningWeb.Components.Credentials.credential_modal
        id={"credential-#{@id}"}
        width="max-w-md"
      >
        <:title>
          Delete credential
        </:title>
        <div class="text-sm text-gray-500">
          <p class="">
            Deleting this credential will immediately remove it from all jobs and
            projects. If you later restore it, you will need to re-share it with
            projects and re-associate it with jobs. Are you sure you'd like to
            delete the credential?
          </p>
          <p :if={@has_activity_in_projects?} class="mt-2 italic text-slate-500">
            *This credential has been used in workflow runs that
            are still monitored in at least one project's audit trail. The
            credential will be made unavailable for future use immediately and
            after a cooling-off period all secrets will be permanently scrubbed,
            but the record itself will not be removed until related workflow
            runs have been purged.
          </p>
        </div>
        <.modal_footer>
          <.button
            id={"user-#{@id}_confirm_button"}
            type="button"
            phx-click="delete"
            phx-value-id={@credential.id}
            phx-target={@myself}
            theme="danger"
            phx-disable-with="Deleting..."
          >
            Delete credential
          </.button>
          <LightningWeb.Components.Credentials.credential_modal_cancel_button modal_id={"credential-#{@id}"} />
        </.modal_footer>
      </LightningWeb.Components.Credentials.credential_modal>
    </div>
    """
  end
end
