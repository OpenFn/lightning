defmodule LightningWeb.DashboardLive.Index do
  @moduledoc false
  use LightningWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:active_menu_item, :dashboard)}
  end

  @impl true
  def handle_params(_, _, socket) do
    {:noreply, socket |> assign(:page_title, page_title(socket.assigns.live_action))}
  end

  defp page_title(:index), do: "Dashboard"
end
