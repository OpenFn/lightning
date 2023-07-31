defmodule LightningWeb.ProjectLive.MFARequired do
  @moduledoc """
  Liveview for project access denied error messages
  """
  use LightningWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, assign(socket, active_menu_item: nil)}
  end

  @impl true
  def handle_params(params, _uri, socket) do
    apply_action(socket, socket.assigns.live_action, params)
  end

  defp apply_action(socket, :index, _params) do
    {:noreply, socket |> assign(page_title: "MFA Required for Project")}
  end
end
