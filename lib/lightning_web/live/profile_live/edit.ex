defmodule LightningWeb.ProfileLive.Edit do
  @moduledoc """
  LiveView for user profile page.
  """
  use LightningWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket}
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply,
     apply_action(
       socket,
       socket.assigns.live_action,
       socket.assigns.current_user
     )}
  end

  defp apply_action(socket, :edit, params) do
    socket
    |> assign(:page_title, "Settings")
    |> assign(:user, params)
  end
end
