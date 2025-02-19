defmodule LightningWeb.CredentialLive.TransferCredentialModal do
  @moduledoc """
  Form Component for working with a single Credential
  """
  use LightningWeb, :live_component

  import Lightning.Accounts.User,
    only: [
      validate_email_format: 1,
      validate_email_not_exists: 1,
      validate_project_access: 2,
      validate_not_same_user: 4
    ]

  alias Lightning.Accounts
  alias Lightning.Credentials

  @impl true
  def update(assigns, socket) do
    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, empty_email_changeset())}
  end

  @impl true
  def handle_event("close-modal", _params, socket) do
    {:noreply, push_navigate(socket, to: socket.assigns.return_to)}
  end

  def handle_event("validate", %{"receiver" => %{"email" => email}}, socket) do
    changeset = build_email_changeset(email) |> Map.put(:action, :validate)
    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("check_user_access", %{"value" => email}, socket) do
    %{assigns: %{current_user: current_user, credential: credential}} = socket

    changeset =
      build_email_changeset(email)
      |> validate_credential_transfer(current_user, credential)

    {:noreply, assign(socket, :changeset, changeset)}
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
      build_email_changeset(email)
      |> validate_credential_transfer(owner, credential)

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
    <div class="text-left mt-10 sm:mt-0">
      <.modal id={@id} width="xl:min-w-1/3 min-w-1/2 w-[300px]">
        <:title>
          <div class="flex justify-between">
            <span class="font-bold">Transfer Credential Ownership</span>
            <.close_button id={@id} myself={@myself} />
          </div>
        </:title>
        <:subtitle>
          <span class="text-xs">
            Enter the email address of the user to whom you want to transfer the ownership of this credential
          </span>
        </:subtitle>
        <.form_component id={@id} changeset={@changeset} myself={@myself} />
      </.modal>
    </div>
    """
  end

  defp validate_credential_transfer(changeset, current_user, credential) do
    changeset
    |> validate_email_format()
    |> then(fn changeset ->
      if changeset.valid? do
        changeset
        |> validate_email_not_exists()
        |> validate_not_same_user(:email, current_user,
          message: "You cannot transfer a credential to yourself"
        )
        |> validate_project_access(credential)
      else
        changeset
      end
    end)
    |> Map.put(:action, :validate)
  end

  defp build_email_changeset(email) do
    empty_email_changeset()
    |> Ecto.Changeset.cast(%{email: email}, [:email])
  end

  defp empty_email_changeset do
    Ecto.Changeset.cast({%{}, %{email: :string}}, %{}, [:email])
  end

  defp close_button(assigns) do
    ~H"""
    <button
      id={"close-credential-modal-form-#{@id || "new"}"}
      phx-click="close-modal"
      phx-target={@myself}
      type="button"
      class="rounded-md bg-white text-gray-400 hover:text-gray-500 focus:outline-none"
      aria-label={gettext("close")}
    >
      <span class="sr-only">Close</span>
      <.icon name="hero-x-mark" class="h-5 w-5 stroke-current" />
    </button>
    """
  end

  defp form_component(assigns) do
    ~H"""
    <.form
      :let={f}
      id={"#{@id}-form"}
      as={:receiver}
      for={@changeset}
      phx-target={@myself}
      phx-change="validate"
      phx-submit="transfer-credential"
    >
      <.form_fields f={f} myself={@myself} />
      <.form_footer id={@id} myself={@myself} changeset={@changeset} />
    </.form>
    """
  end

  defp form_fields(assigns) do
    ~H"""
    <div class="px-6 space-y-5">
      <div class="flex items-center space-x-4">
        <div class="flex-1">
          <.input
            type="text"
            field={@f[:email]}
            placeholder="email@example.com"
            required="true"
            class="w-full"
            phx-target={@myself}
            phx-blur="check_user_access"
          />
        </div>
      </div>
    </div>
    """
  end

  defp form_footer(assigns) do
    ~H"""
    <.modal_footer class="mx-6 mt-6">
      <div class="flex flex-row-reverse gap-4">
        <.button
          id={"#{@id}-submit-button"}
          type="submit"
          phx-disable-with="Transferring..."
          disabled={!@changeset.valid?}
        >
          Transfer
        </.button>
        <button
          id={"#{@id}-cancel-button"}
          type="button"
          phx-target={@myself}
          phx-click="close-modal"
          class="inline-flex items-center rounded-md bg-white px-3.5 py-2.5 text-sm font-semibold text-gray-900 shadow-sm ring-1 ring-inset ring-gray-300 hover:bg-gray-50"
        >
          Cancel
        </button>
      </div>
    </.modal_footer>
    """
  end
end
