defmodule LightningWeb.UserLive.Edit do
  @moduledoc """
  LiveView for editing a single job, which inturn uses `LightningWeb.JobLive.BigFormComponent`
  for common functionality.
  """
  use LightningWeb, :live_view

  alias Lightning.Accounts

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket, layout: {LightningWeb.LayoutView, "settings.html"}}
  end

  @impl true
  def handle_params(%{"id" => id}, _, socket) do
    {:noreply,
     socket
     |> assign(:page_title, page_title(socket.assigns.live_action))
     |> assign(:active_menu_item, :users)
     |> assign(:user, Accounts.get_user!(id))}
  end

  defp page_title(:show), do: "Show User"
  defp page_title(:edit), do: "Edit User"
end
