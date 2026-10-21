defmodule LightningWeb.BackupCodesLive.Index do
  @moduledoc """
  LiveView for user backup codes.
  """
  use LightningWeb, :live_view
  alias Lightning.Accounts

  on_mount {LightningWeb.Hooks, :assign_projects}

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

    case Accounts.regenerate_user_backup_codes(current_user) do
      {:ok, user} ->
        {:reply, %{},
         socket
         |> put_flash(:info, "New Backup Codes Generated!")
         |> assign(backup_codes: user.backup_codes)}

      {:error, _changeset} ->
        reply_error(socket, "Could not generate new backup codes")
    end
  end

  defp apply_action(socket, :index, _params) do
    socket
    |> assign(:page_title, "Two-factor backup codes")
    |> assign(
      :backup_codes,
      Accounts.list_user_backup_codes(socket.assigns.current_user)
    )
  end

  # The shape the design system's BackupCode type expects: the code and when
  # it was used, nothing else about the row.
  defp codes_json(backup_codes) do
    Enum.map(backup_codes, &%{code: &1.code, usedAt: &1.used_at})
  end
end
