defmodule LightningWeb.DataclipLive.Edit do
  @moduledoc """
  LiveView for editing a single dataclip.
  """
  use LightningWeb, :live_view

  alias Lightning.Invocation
  alias Lightning.Invocation.Dataclip

  on_mount {LightningWeb.Hooks, :project_scope}

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     socket
     |> assign(active_menu_item: :dataclips)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Dataclip")
    |> assign(:dataclip, Invocation.get_dataclip_details!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Dataclip")
    |> assign(:dataclip, %Dataclip{project_id: socket.assigns.project.id})
  end
end
