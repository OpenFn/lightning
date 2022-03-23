defmodule LightningWeb.DataclipLive.FormComponent do
  @moduledoc """
  LiveView component for creating and editing a single `DataClip`
  """
  use LightningWeb, :live_component

  alias Lightning.Invocation

  @impl true
  def update(%{dataclip: dataclip} = assigns, socket) do
    changeset = Invocation.change_dataclip(dataclip)

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)}
  end

  @impl true
  def handle_event("validate", %{"dataclip" => dataclip_params}, socket) do
    changeset =
      socket.assigns.dataclip
      |> Invocation.change_dataclip(dataclip_params)
      |> Map.put(:action, :validate)

    {:noreply, assign(socket, :changeset, changeset)}
  end

  def handle_event("save", %{"dataclip" => dataclip_params}, socket) do
    save_dataclip(socket, socket.assigns.action, dataclip_params)
  end

  defp save_dataclip(socket, :edit, dataclip_params) do
    case Invocation.update_dataclip(socket.assigns.dataclip, dataclip_params) do
      {:ok, _dataclip} ->
        {:noreply,
         socket
         |> put_flash(:info, "Dataclip updated successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, :changeset, changeset)}
    end
  end

  defp save_dataclip(socket, :new, dataclip_params) do
    case Invocation.create_dataclip(dataclip_params) do
      {:ok, _dataclip} ->
        {:noreply,
         socket
         |> put_flash(:info, "Dataclip created successfully")
         |> push_redirect(to: socket.assigns.return_to)}

      {:error, %Ecto.Changeset{} = changeset} ->
        {:noreply, assign(socket, changeset: changeset)}
    end
  end
end
