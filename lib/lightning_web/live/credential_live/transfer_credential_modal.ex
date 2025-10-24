defmodule LightningWeb.CredentialLive.TransferCredentialModal do
  @moduledoc """
  Form Component for working with a single Credential
  """
  use LightningWeb, :live_component

  alias Lightning.Accounts
  alias Lightning.Credentials

  @impl true
  def update(assigns, socket) do
    revoke_transfer = assigns.credential.transfer_status == :pending

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:revoke_transfer, revoke_transfer)
     |> assign(:changeset, Credentials.credential_transfer_changeset())
     |> assign_new(:modal_id, fn %{id: id} -> "#{id}-modal" end)}
  end

  @impl true
  def handle_event("validate", %{"receiver" => %{"email" => email}}, socket) do
    changeset =
      Credentials.credential_transfer_changeset(email)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("check-user-access", %{"value" => email}, socket) do
    %{assigns: %{current_user: current_user, credential: credential}} = socket

    changeset =
      Credentials.credential_transfer_changeset(email)
      |> Credentials.validate_credential_transfer(current_user, credential)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("revoke-transfer", _params, socket) do
    %{
      assigns: %{
        current_user: owner,
        credential: credential,
        return_to: return_to
      }
    } = socket

    case Credentials.revoke_transfer(credential.id, owner) do
      {:ok, _credential} ->
        {:noreply,
         socket
         |> put_flash(:info, "Transfer revoked successfully")
         |> push_navigate(to: return_to)}

      {:error, reason} ->
        {:noreply,
         put_flash(
           socket,
           :error,
           "Could not revoke transfer: #{inspect(reason)}"
         )
         |> push_navigate(to: return_to)}
    end
  end

  def handle_event(
        "transfer-credential",
        %{"receiver" => %{"email" => email}},
        socket
      ) do
    %{
      assigns: %{
        current_user: owner,
        credential: credential,
        return_to: return_to
      }
    } = socket

    changeset =
      Credentials.credential_transfer_changeset(email)
      |> Credentials.validate_credential_transfer(owner, credential)

    if changeset.valid? do
      with receiver when not is_nil(receiver) <-
             Accounts.get_user_by_email(email),
           :ok <-
             Credentials.initiate_credential_transfer(
               owner,
               receiver,
               credential
             ) do
        {:noreply,
         socket
         |> put_flash(
           :info,
           "Credential transfer initiated. We've sent you a confirmation email."
         )
         |> push_navigate(to: return_to)}
      else
        nil ->
          {:noreply, put_flash(socket, :error, "User not found")}

        {:error, reason} ->
          {:noreply,
           put_flash(socket, :error, "Transfer failed: #{inspect(reason)}")}
      end
    else
      {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  @impl true
  def render(assigns) do
    ~H"""
    <div id={@id} class="text-left mt-10 sm:mt-0">
      <Components.Credentials.credential_modal
        id={@modal_id}
        width="xl:min-w-1/3 min-w-1/2 w-[300px]"
      >
        <:title>
          <%= if @revoke_transfer do %>
            Revoke Credential Transfer
          <% else %>
            Transfer Credential Ownership
          <% end %>
        </:title>
        <div class="text-sm leading-4.5 text-zinc-600 mb-4">
          <%= if @revoke_transfer do %>
            A transfer of this credential is pending. Click the revoke button to cancel it.
          <% else %>
            Enter the email address of the new owner. Note: The user must be a member of all projects where this credential is used.
          <% end %>
        </div>
        <.modal_content {assigns} />
      </Components.Credentials.credential_modal>
    </div>
    """
  end

  defp form_component(assigns) do
    ~H"""
    <.form
      :let={f}
      id={"#{@modal_id}-form"}
      as={:receiver}
      for={@changeset}
      phx-target={@myself}
      phx-change="validate"
      phx-submit="transfer-credential"
    >
      <.form_fields f={f} myself={@myself} />
      <.form_footer modal_id={@modal_id} myself={@myself} changeset={@changeset} />
    </.form>
    """
  end

  defp form_fields(assigns) do
    ~H"""
    <div class="space-y-5">
      <div class="flex items-center space-x-4">
        <div class="flex-1">
          <.input
            type="text"
            field={@f[:email]}
            placeholder="email@example.com"
            required="true"
            class="w-full"
            phx-target={@myself}
            phx-blur="check-user-access"
          />
        </div>
      </div>
    </div>
    """
  end

  defp form_footer(assigns) do
    ~H"""
    <.modal_footer>
      <.footer_buttons {assigns} />
    </.modal_footer>
    """
  end

  defp modal_content(%{revoke_transfer: true} = assigns) do
    ~H"""
    <div>
      <p class="text-sm text-gray-600">
        Revoking this transfer will cancel the pending request. This will keep the credential under your ownership. You will need to initiate a new transfer request to transfer it in the future.
      </p>
      <.form_footer {assigns} />
    </div>
    """
  end

  defp modal_content(assigns) do
    ~H"""
    <.form_component modal_id={@modal_id} changeset={@changeset} myself={@myself} />
    """
  end

  defp footer_buttons(%{revoke_transfer: true} = assigns) do
    ~H"""
    <.button
      id={"#{@modal_id}-revoke-button"}
      type="button"
      theme="primary"
      phx-click="revoke-transfer"
      phx-target={@myself}
      phx-disable-with="Revoking..."
    >
      Revoke
    </.button>
    <Components.Credentials.cancel_button
      id={"#{@modal_id}-cancel-button"}
      modal_id={@modal_id}
    />
    """
  end

  defp footer_buttons(assigns) do
    ~H"""
    <.button
      id={"#{@modal_id}-submit-button"}
      type="submit"
      theme="primary"
      phx-disable-with="Transferring..."
      disabled={!@changeset.valid?}
    >
      Transfer
    </.button>
    <Components.Credentials.cancel_button
      id={"#{@modal_id}-cancel-button"}
      modal_id={@modal_id}
    />
    """
  end
end
