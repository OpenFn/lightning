defmodule LightningWeb.BackupCodesLive.Index do
  @moduledoc """
  LiveView for user backup codes.
  """
  use LightningWeb, :live_view
  alias Lightning.Accounts
  alias Phoenix.LiveView.JS

  @impl true
  def mount(_params, _session, socket) do
    {:ok, socket |> assign(:active_menu_item, :profile)}
  end

  @impl true
  def handle_params(params, _url, socket) do
    {:noreply,
     apply_action(
       socket,
       socket.assigns.live_action,
       params
     )}
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Two-factor backup codes")
    |> assign(
      :backup_codes,
      Accounts.list_user_backup_codes(socket.assigns.current_user)
    )
  end
end
