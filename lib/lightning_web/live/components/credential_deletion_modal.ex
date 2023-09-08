defmodule LightningWeb.Components.CredentialDeletionModal do
  @moduledoc false
  alias Lightning.Credentials.Credential
  use LightningWeb, :component

  use Phoenix.LiveComponent

  alias Lightning.Credentials

  @impl true
  def update(
        %{credential: credential} = assigns,
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
             |> push_navigate(to: ~p"/credentials")}

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
         |> push_patch(to: ~p"/credentials")}

      true ->
        Credentials.delete_credential(credential)

        {:noreply,
         socket
         |> put_flash(:info, "Credential deleted successfully")
         |> push_navigate(to: ~p"/credentials")}
    end
  end

  @impl true
  def handle_event("close_modal", _, socket) do
    {:noreply, push_redirect(socket, to: ~p"/credentials")}
  end

  @impl true
  def render(%{delete_now?: true, has_activity_in_projects?: true} = assigns) do
    ~H"""
    <div id={"credential-#{@id}"}>
      <PetalComponents.Modal.modal
        max_width="sm"
        title="Delete credential"
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
    <div id={"credential-#{@id}"}>
      <PetalComponents.Modal.modal
        max_width="sm"
        title="Delete credential"
        close_modal_target={@myself}
      >
        <p>
          Deleting this credential will remove it from all projects and jobs, even if it is currently in use. Are you sure you'd like to delete the credential?
        </p>

        <%= if @has_activity_in_projects? do %>
          <div class="hidden sm:block" aria-hidden="true">
            <div class="py-2"></div>
          </div>
          <p>
            *Note that this credential still has activity related to active projects. We may not be able to delete it entirely from the app until those activities are expired.
          </p>
        <% end %>
        <div class="hidden sm:block" aria-hidden="true">
          <div class="py-2"></div>
        </div>
        <div class="flex justify-end">
          <PetalComponents.Button.button
            label="Cancel"
            phx-click={PetalComponents.Modal.hide_modal(@myself)}
          /> &nbsp;
          <LightningWeb.Components.Common.button
            phx-click="delete"
            phx-value-id={@credential.id}
            phx-target={@myself}
            color="red"
            phx-disable-with="Deleting..."
          >
            Delete credential
          </LightningWeb.Components.Common.button>
        </div>
      </PetalComponents.Modal.modal>
    </div>
    """
  end
end
