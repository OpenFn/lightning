defmodule LightningWeb.DataclipLive.FormComponent do
  @moduledoc """
  Form Component for working with a single dataclip
  """
  use LightningWeb, :live_component

  alias Lightning.Invocation
  import LightningWeb.Components.Form

  @impl true
  def update(%{dataclip: dataclip, project: project} = assigns, socket) do
    types = Lightning.Invocation.Dataclip.source_types()

    changeset =
      Invocation.change_dataclip(dataclip, %{"project_id" => project.id})

    {:ok,
     socket
     |> assign(assigns)
     |> assign(:changeset, changeset)
     |> assign(:types, Enum.zip(types, types))}
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
    project_id =
      Ecto.Changeset.fetch_field!(socket.assigns.changeset, :project_id)

    case Invocation.create_dataclip(
           dataclip_params
           |> Map.put("project_id", project_id)
         ) do
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
