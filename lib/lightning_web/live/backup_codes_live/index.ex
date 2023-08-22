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

  @impl true
  def handle_event("regenerate-backup-codes", _params, socket) do
    current_user = socket.assigns.current_user
    {:ok, user} = Accounts.regenerate_user_backup_codes(current_user)

    {:noreply,
     socket
     |> put_flash(:info, "New Backup Codes Generated!")
     |> assign(backup_codes: user.backup_codes)}
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
