defmodule LightningWeb.DataclipLive.Index do
  @moduledoc """
  LiveView for listing and working with a list of Dataclips
  """
  use LightningWeb, :live_view

  alias Lightning.Invocation
  alias Lightning.Invocation.Dataclip

  @impl true
  def mount(_params, _session, socket) do
    {:ok,
     assign(socket, :dataclips, list_dataclips())
     |> assign(:active_menu_item, :dataclips)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply, apply_action(socket, socket.assigns.live_action, params)}
  end

  defp apply_action(socket, :edit, %{"id" => id}) do
    socket
    |> assign(:page_title, "Edit Dataclip")
    |> assign(:dataclip, Invocation.get_dataclip!(id))
  end

  defp apply_action(socket, :new, _params) do
    socket
    |> assign(:page_title, "New Dataclip")
    |> assign(:dataclip, %Dataclip{})
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Listing Dataclips")
    |> assign(:dataclip, nil)
  end

  @impl true
  def handle_event("delete", %{"id" => id}, socket) do
    dataclip = Invocation.get_dataclip!(id)
    {:ok, _} = Invocation.delete_dataclip(dataclip)

    {:noreply, assign(socket, :dataclips, list_dataclips())}
  end

  defp list_dataclips do
    Invocation.list_dataclips()
  end
end
