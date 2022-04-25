defmodule LightningWeb.CredentialLive.FormComponent do
  @moduledoc """
  Form Component for working with a single Credential
  """
  use LightningWeb, :live_component

  alias Lightning.{Credentials}

  @impl true
  def update(%{credential: credential} = assigns, socket) do
    changeset = Credentials.change_credential(credential)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("validate", %{"credential" => credential_params}, socket) do
    changeset =
      socket.assigns.credential
      |> Credentials.change_credential(credential_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"credential" => credential_params}, socket) do
    save_credential(socket, socket.assigns.action, credential_params)
  end

  defp save_credential(socket, :edit, credential_params) do
    case Credentials.update_credential(
           socket.assigns.credential,
           credential_params
         ) do
      {:ok, _credential} ->
        {:noreply,
         socket
         |> put_flash(:info, "Credential updated successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_credential(socket, :new, credential_params) do
    case Credentials.create_credential(credential_params) do
      {:ok, _credential} ->
        {:noreply,
         socket
         |> put_flash(:info, "Credential created successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end
end
