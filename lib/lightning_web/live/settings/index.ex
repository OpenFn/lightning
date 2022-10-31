defmodule LightningWeb.SettingsLive.Index do
  @moduledoc """
  Index page for listing users
  """
  use LightningWeb, :live_view

  @impl true
  def mount(_params, _session, socket) do
    case Bodyguard.permit(
           Lightning.Accounts.Policy,
           :index,
           socket.assigns.current_user
         ) do
      :ok ->
        {:ok, socket |> assign(:active_menu_item, :settings),
         layout: {LightningWeb.LayoutView, :settings}}

      {:error, :unauthorized} ->
        {:ok,
         put_flash(socket, :error, "You can't access that page")
         |> push_redirect(to: "/")}
    end
  end

  @impl true
  def handle_params(_params, _url, socket) do
    {:noreply, socket}
  end
end
